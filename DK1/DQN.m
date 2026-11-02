% DQN.m - Deep Q-Learning (Double DQN) em Octave puro, mesmo molde do HQlearn.
%
% Entradas/saidas identicas ao HQlearn:
%   [inputs, Fx, Fy] = DQN(mx, my, sprite, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy)
%   Reset: DQN(-1, 0, 0, mapa, [], [], [], [], [], [], [], [])
%
% ACOES: 1=sobe 2=desce 3=esq 4=dir 5=pulo 6=dir+pulo 7=esq+pulo 8=nada
%
% Diferencas para o HQlearn:
%   - em vez de tabela Q, uma MLP  (N_ENTRADA -> 64 -> 64 -> 8)
%   - estado CONTINUO (posicoes normalizadas, barris mais proximos, etc.)
%   - replay buffer + target network + Adam + perda de Huber
%   - o controlador continua guiando (p_guia decai) e dando bonus de imitacao
%
% Dependencias: controlador_mario.m (o mesmo que o HQlearn usa).

function [inputs, Fx, Fy] = DQN(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy)
    % ======================================================================
    % CONSTANTES
    % ======================================================================
    NUM_ACOES = 8;
    N_ENTRADA = 28;          % tamanho do vetor de estado
    N_OCULTA  = 64;

    % --- DQN ---
    GAMMA          = 0.95;
    LR             = 1e-3;   % Adam
    BATCH          = 32;
    BUFFER_TAM     = 20000;
    MIN_BUFFER     = 1000;   % so treina depois disso
    TREINAR_A_CADA = 4;      % frames
    TARGET_A_CADA  = 500;    % passos de treino
    REWARD_SCALE   = 0.01;

    % --- Guia do controlador ---
    P_GUIA_INI        = 0.8;
    P_GUIA_MIN        = 0.1;
    P_GUIA_DECAIMENTO = 0.99997;
    BONUS_IMITACAO    = 1;

    % --- Exploracao ---
    EPS_INICIAL    = 0.10;
    EPS_MIN        = 0.02;
    EPS_DECAIMENTO = 0.99997;

    % --- Recompensas (mesmas do HQlearn) ---
    PUNICAO_PULO       = -2.0;
    PUNICAO_ESTAGNACAO = -2;
    LIMITE_ESTAGNACAO  = 200;
    PESO_ALTURA        = 5;
    PESO_DESCIDA       = 10;
    RECOMPENSA_PULO    = 50.0;
    RECOMPENSA_VITORIA = 1000.0;
    RECOMPENSA_MORTE   = -100.0;

    LIMITE_TELEPORTE = 40;
    Y_VITORIA        = 30;

    TOL_ALTURA_ESCADA = 15;
    TOL_ALINHAMENTO   = 3;
    DIST_BARRIL_X = 25;
    DIST_BARRIL_Y = 15;
    HORIZONTE_PREVISAO = 10;
    DIST_FOGUINHO_X = 20;
    DIST_FOGUINHO_Y = 12;

    ARQUIVO_REDE  = 'dqn_rede.mat';
    SALVAR_A_CADA = 2000;    % frames

    % ======================================================================
    % ESTADO PERSISTENTE
    % ======================================================================
    persistent rede alvo adam buffer buf_n buf_i total_frames passos_treino;
    persistent melhor_altura my_anterior;
    persistent s_anterior acao_anterior sugestao_anterior pulou_anterior perigo_barril_anterior frames_sem_subir;

    if isempty(rede)
        rede = []; adam = []; total_frames = 0; passos_treino = 0;
        if exist(ARQUIVO_REDE, 'file')
            [rede, alvo, adam, total_frames, passos_treino] = carregar_rede(ARQUIVO_REDE, N_ENTRADA, N_OCULTA, NUM_ACOES);
        end
        if isempty(rede)
            rede = iniciar_rede(N_ENTRADA, N_OCULTA, NUM_ACOES);
            alvo = rede;
            adam = iniciar_adam(rede);
            total_frames = 0;
            passos_treino = 0;
        end
        buffer = zeros(BUFFER_TAM, 2*N_ENTRADA + 3);
        buf_n = 0;
        buf_i = 0;
        frames_sem_subir       = 0;
        melhor_altura          = NaN;
        my_anterior            = NaN;
        s_anterior             = [];
        acao_anterior          = 0;
        sugestao_anterior      = 0;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
    end

    inputs = zeros(1, 8);
    Fx = NaN;
    Fy = NaN;

    % ======================================================================
    % RESET EXPLICITO (main chama com mx == -1) -> transicao pendente = morte
    % ======================================================================
    if mx == -1
        if ~isempty(s_anterior)
            [buffer, buf_i, buf_n] = guardar(buffer, buf_i, buf_n, BUFFER_TAM, ...
                s_anterior, acao_anterior, RECOMPENSA_MORTE * REWARD_SCALE, s_anterior, 1);
        end
        frames_sem_subir       = 0;
        s_anterior             = [];
        melhor_altura          = NaN;
        my_anterior            = NaN;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
        salvar_rede(ARQUIVO_REDE, rede, alvo, adam, total_frames, passos_treino);
        return;
    end

    % Mario sumiu: nao aprende nesse frame
    if isnan(mx) || isnan(my) || mx == 0
        return;
    end

    if isnan(melhor_altura)
        melhor_altura = my;
    end

    % ======================================================================
    % Teleporte (reset nao explicito)
    % ======================================================================
    if ~isnan(my_anterior) && abs(my - my_anterior) > LIMITE_TELEPORTE
        if ~isempty(s_anterior) && my_anterior >= Y_VITORIA
            [buffer, buf_i, buf_n] = guardar(buffer, buf_i, buf_n, BUFFER_TAM, ...
                s_anterior, acao_anterior, RECOMPENSA_MORTE * REWARD_SCALE, s_anterior, 1);
        end
        frames_sem_subir       = 0;
        s_anterior             = [];
        melhor_altura          = my;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
    end
    if ~isnan(my_anterior)
        delta_y = my_anterior - my;   % >0 subiu
    else
        delta_y = 0;
    end
    my_anterior = my;

    % ======================================================================
    % Controlador roda todo frame e sugere uma acao
    % ======================================================================
    [inputs_ctrl, Fx_ctrl, Fy_ctrl] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
    if numel(inputs_ctrl) ~= 8
        inputs_ctrl = zeros(1, 8);
    end
    sugestao = inputs_para_acao(inputs_ctrl);

    % ======================================================================
    % Estado atual (vetor continuo, coluna)
    % ======================================================================
    [escada_bin, ~] = avaliar_escada(mx, my, mapa, TOL_ALTURA_ESCADA, TOL_ALINHAMENTO);
    [perigo_barril_bin, dir_barril_bin] = avaliar_perigo_barril(mx, my, bx, by, bpx, bpy, DIST_BARRIL_X, DIST_BARRIL_Y, HORIZONTE_PREVISAO);
    [perigo_fogo_bin, dir_fogo_bin] = avaliar_perigo_foguinho(mx, my, fx, fy, DIST_FOGUINHO_X, DIST_FOGUINHO_Y);

    s_atual = construir_estado(mx, my, sprite_atual_mario, escada_bin, bx, by, fx, fy, ...
        perigo_barril_bin, dir_barril_bin, perigo_fogo_bin, dir_fogo_bin, sugestao);
    if numel(s_atual) ~= N_ENTRADA
        error('DQN: N_ENTRADA=%d mas construir_estado devolveu %d valores.', N_ENTRADA, numel(s_atual));
    end

    p_guia    = max(P_GUIA_MIN, P_GUIA_INI * (P_GUIA_DECAIMENTO ^ total_frames));
    eps_atual = max(EPS_MIN, EPS_INICIAL * (EPS_DECAIMENTO ^ total_frames));

    % ======================================================================
    % Recompensa da transicao (s_anterior -> s_atual)
    % ======================================================================
    if ~isempty(s_anterior)
        recompensa = 0;

        if acao_anterior == sugestao_anterior
            recompensa = recompensa + BONUS_IMITACAO * (p_guia / P_GUIA_INI);
        end

        if delta_y > 0
            recompensa = recompensa + delta_y * PESO_ALTURA;
        elseif delta_y < 0
            recompensa = recompensa + delta_y * PESO_DESCIDA;
        end

        if my < melhor_altura
            melhor_altura = my;
            frames_sem_subir = 0;
        else
            frames_sem_subir = frames_sem_subir + 1;
        end
        if frames_sem_subir > LIMITE_ESTAGNACAO
            recompensa = recompensa + PUNICAO_ESTAGNACAO;
        end

        if pulou_anterior
            if perigo_barril_anterior >= 1 && perigo_barril_bin == 0
                recompensa = recompensa + RECOMPENSA_PULO;
            else
                recompensa = recompensa + PUNICAO_PULO;
            end
        end

        venceu = (my < Y_VITORIA);
        if venceu
            recompensa = recompensa + RECOMPENSA_VITORIA;
        end

        [buffer, buf_i, buf_n] = guardar(buffer, buf_i, buf_n, BUFFER_TAM, ...
            s_anterior, acao_anterior, recompensa * REWARD_SCALE, s_atual, venceu);

        if venceu
            frames_sem_subir       = 0;
            s_anterior             = [];
            melhor_altura          = NaN;
            pulou_anterior         = false;
            perigo_barril_anterior = 0;
            salvar_rede(ARQUIVO_REDE, rede, alvo, adam, total_frames, passos_treino);
            return;
        end
    end

    % ======================================================================
    % Treino (a cada TREINAR_A_CADA frames, depois que o buffer encheu um pouco)
    % ======================================================================
    if buf_n >= MIN_BUFFER && mod(total_frames, TREINAR_A_CADA) == 0
        [rede, adam] = treinar_minibatch(rede, alvo, adam, buffer, buf_n, N_ENTRADA, BATCH, GAMMA, LR);
        passos_treino = passos_treino + 1;
        if mod(passos_treino, TARGET_A_CADA) == 0
            alvo = rede;
        end
    end

    % ======================================================================
    % Escolha da acao
    %   1) buffer ainda pequeno ou sorteio < p_guia -> controlador
    %   2) sorteio seguinte < eps                    -> aleatoria
    %   3) senao                                     -> argmax Q(s)
    % ======================================================================
    r = rand();
    seguiu_controlador = false;

    if buf_n < MIN_BUFFER || r < p_guia
        acao_atual = sugestao;
        seguiu_controlador = true;
    elseif r < p_guia + eps_atual
        acao_atual = randi(NUM_ACOES);
    else
        q = forward(rede, s_atual);
        melhores = find(q == max(q));
        acao_atual = melhores(randi(numel(melhores)));
    end

    if seguiu_controlador
        inputs = inputs_ctrl;
        Fx = Fx_ctrl;
        Fy = Fy_ctrl;
    else
        inputs = acao_para_inputs(acao_atual);
    end

    pulou_anterior         = (inputs(7) == 1);
    perigo_barril_anterior = perigo_barril_bin;
    s_anterior             = s_atual;
    acao_anterior          = acao_atual;
    sugestao_anterior      = sugestao;
    total_frames           = total_frames + 1;

    if mod(total_frames, SALVAR_A_CADA) == 0
        salvar_rede(ARQUIVO_REDE, rede, alvo, adam, total_frames, passos_treino);
    end
end


% ==========================================================================
% REDE NEURAL (MLP com ReLU) + ADAM
% ==========================================================================

function W = iniciar_rede(n_in, n_h, n_out)
    W.W1 = randn(n_h, n_in)  * sqrt(2 / n_in);  W.b1 = zeros(n_h, 1);
    W.W2 = randn(n_h, n_h)   * sqrt(2 / n_h);   W.b2 = zeros(n_h, 1);
    W.W3 = randn(n_out, n_h) * 0.01;            W.b3 = zeros(n_out, 1);
end

function adam = iniciar_adam(W)
    adam.t = 0;
    campos = fieldnames(W);
    for i = 1:numel(campos)
        adam.m.(campos{i}) = zeros(size(W.(campos{i})));
        adam.v.(campos{i}) = zeros(size(W.(campos{i})));
    end
end

% X: (n_in x B). Devolve Q (n_out x B) e o cache pro backprop.
function [Q, c] = forward(W, X)
    Z1 = W.W1 * X + W.b1;   H1 = max(0, Z1);
    Z2 = W.W2 * H1 + W.b2;  H2 = max(0, Z2);
    Q  = W.W3 * H2 + W.b3;
    c.X = X; c.Z1 = Z1; c.H1 = H1; c.Z2 = Z2; c.H2 = H2;
end

function [rede, adam] = treinar_minibatch(rede, alvo, adam, buffer, buf_n, N, B, GAMMA, LR)
    idx  = randi(buf_n, 1, B);
    lote = buffer(idx, :);
    S    = lote(:, 1:N)';
    a    = lote(:, N+1)';
    r    = lote(:, N+2)';
    S2   = lote(:, N+3:2*N+2)';
    d    = lote(:, end)';

    % Double DQN: a rede online escolhe a acao, a rede alvo avalia
    q_on   = forward(rede, S2);
    [~, am] = max(q_on, [], 1);
    q_alvo = forward(alvo, S2);
    y = r + GAMMA * (1 - d) .* q_alvo(sub2ind(size(q_alvo), am, 1:B));

    [Q, c] = forward(rede, S);
    ind = sub2ind(size(Q), a, 1:B);
    erro = Q(ind) - y;
    g = max(-1, min(1, erro));          % gradiente da perda de Huber

    dQ = zeros(size(Q));
    dQ(ind) = g / B;

    G.W3 = dQ * c.H2';                  G.b3 = sum(dQ, 2);
    dZ2  = (rede.W3' * dQ) .* (c.Z2 > 0);
    G.W2 = dZ2 * c.H1';                 G.b2 = sum(dZ2, 2);
    dZ1  = (rede.W2' * dZ2) .* (c.Z1 > 0);
    G.W1 = dZ1 * c.X';                  G.b1 = sum(dZ1, 2);

    % Passo do Adam
    b1 = 0.9; b2 = 0.999; e = 1e-8;
    adam.t = adam.t + 1;
    campos = fieldnames(rede);
    for i = 1:numel(campos)
        f = campos{i};
        adam.m.(f) = b1 * adam.m.(f) + (1 - b1) * G.(f);
        adam.v.(f) = b2 * adam.v.(f) + (1 - b2) * (G.(f) .^ 2);
        mh = adam.m.(f) / (1 - b1 ^ adam.t);
        vh = adam.v.(f) / (1 - b2 ^ adam.t);
        rede.(f) = rede.(f) - LR * mh ./ (sqrt(vh) + e);
    end
end


% ==========================================================================
% REPLAY BUFFER (circular). Linha = [s, a, r, s2, done]
% ==========================================================================

function [buffer, buf_i, buf_n] = guardar(buffer, buf_i, buf_n, tam, s, a, r, s2, done)
    buf_i = mod(buf_i, tam) + 1;
    buffer(buf_i, :) = [s(:)', a, r, s2(:)', double(done)];
    buf_n = min(buf_n + 1, tam);
end


% ==========================================================================
% ESTADO (todos os valores normalizados em ~[-1, 1])
% Tamanho: 2 + 4 + 1 + 6 + 2 + 2 + 3 + 8 = 28
% ==========================================================================

function s = construir_estado(mx, my, sprite, escada_bin, bx, by, fx, fy, ...
        perigo_barril, dir_barril, perigo_fogo, dir_fogo, sugestao)
    pos      = [mx / 256, my / 240];
    escada   = [escada_bin == -1, escada_bin == 0, escada_bin == 1, escada_bin == 2];
    subindo  = (sprite == 3);
    barris   = feat_proximos(mx, my, bx, by, 2);          % 2 barris mais proximos (dx, dy, presente)
    perigos  = [perigo_barril / 2, dir_barril, perigo_fogo, dir_fogo];
    fogo     = feat_proximos(mx, my, fx, fy, 1);
    sug      = zeros(1, 8);  sug(sugestao) = 1;
    s = double([pos, escada, subindo, barris, perigos, fogo, sug])';
end

function v = feat_proximos(mx, my, xs, ys, k)
    v = zeros(1, 3*k);
    if isempty(xs) || isempty(ys)
        return;
    end
    xs = xs(:); ys = ys(:);
    ok = ~isnan(xs) & ~isnan(ys);
    xs = xs(ok); ys = ys(ok);
    if isempty(xs)
        return;
    end
    [~, ord] = sort(abs(xs - mx) + abs(ys - my));
    for j = 1:min(k, numel(ord))
        i = ord(j);
        v(3*j-2) = max(-1, min(1, (xs(i) - mx) / 100));
        v(3*j-1) = max(-1, min(1, (ys(i) - my) / 60));
        v(3*j)   = 1;
    end
end


% ==========================================================================
% PERSISTENCIA
% ==========================================================================

function salvar_rede(arquivo, rede, alvo, adam, total_frames, passos_treino)
    save('-binary', arquivo, 'rede', 'alvo', 'adam', 'total_frames', 'passos_treino');
end

function [rede, alvo, adam, total_frames, passos_treino] = carregar_rede(arquivo, n_in, n_h, n_out)
    rede = []; alvo = []; adam = []; total_frames = 0; passos_treino = 0;
    try
        d = load(arquivo);
        if isfield(d, 'rede') && isequal(size(d.rede.W1), [n_h, n_in]) && isequal(size(d.rede.W3), [n_out, n_h])
            rede = d.rede; alvo = d.alvo; adam = d.adam;
            total_frames = d.total_frames; passos_treino = d.passos_treino;
            disp(['Rede DQN carregada de ' arquivo]);
        else
            disp('Arquivo da rede DQN incompativel - comecando do zero.');
        end
    catch
        disp('Nao foi possivel carregar a rede DQN - comecando do zero.');
    end
end


% ==========================================================================
% CONVERSAO ACOES <-> INPUTS DO NES
% ==========================================================================

function a = inputs_para_acao(inp)
    cima = inp(3); baixo = inp(4); esq = inp(5); dir = inp(6); pulo = inp(7);
    if pulo && dir && ~esq
        a = 6;
    elseif pulo && esq && ~dir
        a = 7;
    elseif pulo
        a = 5;
    elseif cima
        a = 1;
    elseif baixo
        a = 2;
    elseif esq
        a = 3;
    elseif dir
        a = 4;
    else
        a = 8;
    end
end

function inp = acao_para_inputs(a)
    inp = zeros(1, 8);
    switch a
        case 1, inp(3) = 1;
        case 2, inp(4) = 1;
        case 3, inp(5) = 1;
        case 4, inp(6) = 1;
        case 5, inp(7) = 1;
        case 6, inp(6) = 1; inp(7) = 1;
        case 7, inp(5) = 1; inp(7) = 1;
        otherwise % 8 = nada
    end
end


% ==========================================================================
% AUXILIARES (copiadas do HQlearn)
% ==========================================================================

function [bin, escada_alvo] = avaliar_escada(mx, my, mapa, tol_altura, tol_alinhamento)
    escada_alvo = [];
    idx_validas = [];
    for i = 1:length(mapa.escadas_lista)
        e = mapa.escadas_lista(i);
        if abs(my - e.y_base) <= tol_altura
            idx_validas(end+1) = i;
        end
    end
    if isempty(idx_validas)
        bin = 2;
        return;
    end
    melhor_i = idx_validas(1);
    melhor_d = abs(mapa.escadas_lista(melhor_i).x_centro - mx);
    for k = 2:length(idx_validas)
        i = idx_validas(k);
        d = abs(mapa.escadas_lista(i).x_centro - mx);
        if d < melhor_d
            melhor_d = d;
            melhor_i = i;
        end
    end
    escada_alvo = mapa.escadas_lista(melhor_i);
    dx = escada_alvo.x_centro - mx;
    if abs(dx) <= tol_alinhamento
        bin = 0;
    elseif dx > 0
        bin = 1;
    else
        bin = -1;
    end
end

function [bin, dir_bin] = avaliar_perigo_barril(mx, my, bx, by, bpx, bpy, dist_x, dist_y, horizonte)
    bin = 0;
    dir_bin = 0;
    for i = 1:length(bx)
        if abs(bx(i) - mx) < dist_x && abs(by(i) - my) < dist_y
            bin = 2;
            dir_bin = sign(bx(i) - mx);
            return;
        end
    end
    for i = 1:length(bpx)
        if isempty(bpx{i})
            continue;
        end
        limite = min(horizonte, length(bpx{i}));
        for t = 1:limite
            if abs(bpx{i}(t) - mx) < dist_x && abs(bpy{i}(t) - my) < dist_y
                bin = 1;
                dir_bin = sign(bpx{i}(t) - mx);
                return;
            end
        end
    end
end

function [bin, dir_bin] = avaliar_perigo_foguinho(mx, my, fx, fy, dist_x, dist_y)
    bin = 0;
    dir_bin = 0;
    for i = 1:length(fx)
        if abs(fx(i) - mx) < dist_x && abs(fy(i) - my) < dist_y
            bin = 1;
            dir_bin = sign(fx(i) - mx);
            return;
        end
    end
end