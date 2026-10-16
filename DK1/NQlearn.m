% mx, my              -> posição atual do Mario (filtrada pelo Kalman)
% sprite_atual_mario  -> índice/estado do sprite detectado do Mario
% mapa                -> estrutura contendo plataformas, escadas e demais
% bx, by              -> posição atual de cada barril rastreado (vetores)
% bvx, bvy            -> velocidade estimada de cada barril (px/frame)
% bpx, bpy            -> trajetória prevista dos barris (cell arrays)
% fx, fy              -> posição atual do foguinho
% saidas:
% inputs              -> vetor de entrada do NES: [start select up down left right a b]
% Fx, Fy              -> alvo/objetivo atual do controlador (só preenchido quando o controlador guiou o frame)
%
% ACOES DO Q-LEARNING (todas "cruas", a tabela NAO tem mais a acao "usar controlador"):
%   1 = sobe          5 = pulo
%   2 = desce         6 = direita + pulo
%   3 = esquerda      7 = esquerda + pulo
%   4 = direita       8 = nada
%
% adicionei novas ações necessar
%
% Eu mudei a forma como o controlador do mario operava, eu tirei ele das entradas do qlearn e coloquei
% ele pra rodar todo frame recomendando uma ação pro Qlearn, o qlearn recebe uma pequena recompensa por seguir o 
% controlador, a recompensa decai
function [inputs, Fx, Fy] = NQlearn(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy)
    % ======================================================================
    % CONSTANTES
    % ======================================================================
    NUM_ACOES       = 8;
    ALPHA           = 0.1;    % taxa de aprendizado
    GAMMA           = 0.9;    % desconto do futuro

    % --- Guia do controlador ---
    P_GUIA_INI        = 0.8;      % chance de seguir o controlador no comeco
    P_GUIA_MIN        = 0.1;      % chance minima (0 pra avalia so a tabela)
    P_GUIA_DECAIMENTO = 0.99997;  % por frame (~70k frames ate chegar no minimo)
    MIN_VISITAS       = 3;        % estado com menos visitas -> controlador decide
    BONUS_IMITACAO    = 0.5;      % recompensa por concordar com o controlador (decai com a certeza)
    USAR_SUGESTAO_NO_ESTADO = false;

    % --- Exploracao aleatoria (ajustes recompensa) ---
    EPS_INICIAL     = 0.10;
    EPS_MIN         = 0.02;
    EPS_DECAIMENTO  = 0.99997;

    PUNICAO_PULO    = -1.0;
    PUNICAO_ESTAGNACAO = -2;   % pontos perdidos por frame parado apos o limite
    LIMITE_ESTAGNACAO  = 200;  % frames permitidos sem subir antes de perder pontos

    PESO_ALTURA        = 2;      % pontos por pixel subido
    RECOMPENSA_PULO    = 50.0;   % pontos por desviar de um barril que estava no caminho
    RECOMPENSA_VITORIA = 1000.0; % bonus por vencer
    RECOMPENSA_MORTE   = -100.0; % punicao por morrer

    LIMITE_TELEPORTE = 40;    % px - fallback: se o Mario "pular" mais que isso, foi reset
    Y_VITORIA        = 30;    % px - abaixo disso o Mario venceu a fase

    TOL_ALTURA_ESCADA = 15;   % igual ao usado no controlador_mario
    TOL_ALINHAMENTO   = 3;

    DIST_BARRIL_X = 25;
    DIST_BARRIL_Y = 15;
    HORIZONTE_PREVISAO = 10;  % quantos frames da previsao olhar pra frente

    DIST_FOGUINHO_X = 20;
    DIST_FOGUINHO_Y = 12;

    ARQUIVO_TABELA = 'qlearn_tabela_v2.mat';  % formato novo (8 acoes + contador de visitas)
    SALVAR_A_CADA  = 500;     % frames

    % ======================================================================
    % ESTADO PERSISTENTE
    % Cada linha da tabela Q = [q(1..NUM_ACOES), numero_de_visitas_do_estado]
    % ======================================================================
    persistent Q total_frames melhor_altura my_anterior;
    persistent estado_anterior acao_anterior sugestao_anterior pulou_anterior perigo_barril_anterior frames_sem_subir;

    if isempty(Q)
        if exist(ARQUIVO_TABELA, 'file')
            Q = carregar_Q(ARQUIVO_TABELA, NUM_ACOES);
        else
            Q = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end
        frames_sem_subir        = 0;
        total_frames            = 0;
        melhor_altura           = NaN;
        my_anterior             = NaN;
        estado_anterior         = '';
        acao_anterior           = 0;
        sugestao_anterior       = 0;
        pulou_anterior          = false;
        perigo_barril_anterior  = 0;
    end

    inputs = zeros(1, 8);
    Fx = NaN;
    Fy = NaN;

    % ======================================================================
    % SINAL EXPLICITO DE RESET (chamado pelo main_DK.m com mx == -1)
    % ======================================================================
    if mx == -1
        if ~isempty(estado_anterior)
            % Transicao pendente nesse ponto -> so pode ter sido morte
            linha = pegar_linha(Q, estado_anterior, NUM_ACOES);
            linha(acao_anterior) = linha(acao_anterior) + ALPHA * (RECOMPENSA_MORTE - linha(acao_anterior));
            Q(estado_anterior) = linha;
        end

        frames_sem_subir       = 0;
        estado_anterior        = '';
        melhor_altura          = NaN;
        my_anterior            = NaN;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
        return;
    end

    % Mario sumiu da tela: nao aprende nesse frame, so segura
    if isnan(mx) || isnan(my) || mx == 0
        return;
    end

    if isnan(melhor_altura)
        melhor_altura = my;
    end

    % ======================================================================
    % detecta "teleporte" de posicao caso algum reset aconteca
    % sem passar pelo sinal explicito acima.
    % ======================================================================
    if ~isnan(my_anterior) && abs(my - my_anterior) > LIMITE_TELEPORTE

        if ~isempty(estado_anterior) && my_anterior >= Y_VITORIA
            linha = pegar_linha(Q, estado_anterior, NUM_ACOES);
            linha(acao_anterior) = linha(acao_anterior) + ALPHA * (RECOMPENSA_MORTE - linha(acao_anterior));
            Q(estado_anterior) = linha;
        end

        frames_sem_subir       = 0;
        estado_anterior        = '';
        melhor_altura          = my;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
    end
    my_anterior = my;

    % ======================================================================
    % O controlador roda TODO frame a saida dele vira a sugestao do frame.
    % ======================================================================
    [inputs_ctrl, Fx_ctrl, Fy_ctrl] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
    if numel(inputs_ctrl) ~= 8
        inputs_ctrl = zeros(1, 8);
    end
    sugestao = inputs_para_acao(inputs_ctrl);

    % ======================================================================
    % Monta o estado atual (discretizado)
    % ======================================================================
    [escada_bin, ~] = avaliar_escada(mx, my, mapa, TOL_ALTURA_ESCADA, TOL_ALINHAMENTO);
    subindo_bin = (sprite_atual_mario == 3);
    [perigo_barril_bin, dir_barril_bin] = avaliar_perigo_barril(mx, my, bx, by, bpx, bpy, DIST_BARRIL_X, DIST_BARRIL_Y, HORIZONTE_PREVISAO);
    [perigo_fogo_bin, dir_fogo_bin] = avaliar_perigo_foguinho(mx, my, fx, fy, DIST_FOGUINHO_X, DIST_FOGUINHO_Y);

    if USAR_SUGESTAO_NO_ESTADO
        estado_atual = sprintf('%d|%d|%d|%d|%d|%d|%d', escada_bin, subindo_bin, perigo_barril_bin, ...
            dir_barril_bin, perigo_fogo_bin, dir_fogo_bin, sugestao);
    else
        estado_atual = sprintf('%d|%d|%d|%d|%d|%d', escada_bin, subindo_bin, perigo_barril_bin, ...
            dir_barril_bin, perigo_fogo_bin, dir_fogo_bin);
    end

    % Probabilidades atuais (usadas na recompensa e na escolha)
    p_guia = max(P_GUIA_MIN, P_GUIA_INI * (P_GUIA_DECAIMENTO ^ total_frames));
    eps_atual = max(EPS_MIN, EPS_INICIAL * (EPS_DECAIMENTO ^ total_frames));

    % ======================================================================
    % Recompensa da transicao (estado_anterior -> estado_atual)
    % ======================================================================
    if ~isempty(estado_anterior)
        recompensa = 0;

        % Bonus de imitacao: concordar com o controlador vale um pouco,
        % mas decai conforme o Qlearn deixa de depender dele.
        if acao_anterior == sugestao_anterior
            recompensa = recompensa + BONUS_IMITACAO * (p_guia / P_GUIA_INI);
        end

        if my < melhor_altura
            ganho = melhor_altura - my;
            melhor_altura = my;
            recompensa = recompensa + ganho * PESO_ALTURA;
            frames_sem_subir = 0;
        else
            frames_sem_subir = frames_sem_subir + 1;
        end

        if frames_sem_subir > LIMITE_ESTAGNACAO
            recompensa = recompensa + PUNICAO_ESTAGNACAO;
        end

        % Pontos por desviar de um barril que REALMENTE estava no caminho
        if pulou_anterior
            if perigo_barril_anterior >= 1 && perigo_barril_bin == 0
                recompensa = recompensa + RECOMPENSA_PULO;
            else
                recompensa = recompensa + PUNICAO_PULO;
            end
        end

        if my < Y_VITORIA
            recompensa = recompensa + RECOMPENSA_VITORIA;
        end

        % ------------------------------------------------------------
        % Atualiza a tabela Q (Q-learning classico, off-policy)
        % ------------------------------------------------------------
        linha_ant = pegar_linha(Q, estado_anterior, NUM_ACOES);
        linha_atu = pegar_linha(Q, estado_atual, NUM_ACOES);
        max_futuro = max(linha_atu(1:NUM_ACOES));

        q_antigo = linha_ant(acao_anterior);
        linha_ant(acao_anterior) = q_antigo + ALPHA * (recompensa + GAMMA * max_futuro - q_antigo);
        Q(estado_anterior) = linha_ant;

        % Venceu: fecha o episodio e salva
        if my < Y_VITORIA
            frames_sem_subir       = 0;
            estado_anterior        = '';
            melhor_altura          = NaN;
            pulou_anterior         = false;
            perigo_barril_anterior = 0;
            salvar_Q(Q, ARQUIVO_TABELA);
            return;
        end
    end

    % ======================================================================
    % Escolhe a proxima acao
    %   1) estado pouco conhecido ou sorteio < p_guia -> segue o controlador
    %   2) sorteio seguinte < eps                     -> aleatoria
    %   3) senao                                      -> greedy na tabela
    % ======================================================================
    linha = pegar_linha(Q, estado_atual, NUM_ACOES);
    visitas = linha(NUM_ACOES + 1);

    r = rand();
    seguiu_controlador = false;

    if visitas < MIN_VISITAS || r < p_guia
        acao_atual = sugestao;
        seguiu_controlador = true;
    elseif r < p_guia + eps_atual
        acao_atual = randi(NUM_ACOES);
    else
        valores = linha(1:NUM_ACOES);
        melhores = find(valores == max(valores));
        acao_atual = melhores(randi(numel(melhores)));   % desempate aleatorio
    end

    linha(NUM_ACOES + 1) = visitas + 1;
    Q(estado_atual) = linha;

    % ======================================================================
    % Executa a acao escolhida
    % ======================================================================
    if seguiu_controlador
        inputs = inputs_ctrl;   % usa a saida exata do controlador (mais fiel que a acao quantizada)
        Fx = Fx_ctrl;
        Fy = Fy_ctrl;
    else
        inputs = acao_para_inputs(acao_atual);
    end

    pulou_anterior         = (inputs(7) == 1);
    perigo_barril_anterior = perigo_barril_bin;

    estado_anterior   = estado_atual;
    acao_anterior     = acao_atual;
    sugestao_anterior = sugestao;
    total_frames      = total_frames + 1;

    if mod(total_frames, SALVAR_A_CADA) == 0
        salvar_Q(Q, ARQUIVO_TABELA);
    end

end


% ==========================================================================
% CONVERSAO ENTRE ACOES DO Q-LEARNING E INPUTS DO NES
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

% Devolve a linha [q(1..n), visitas] do estado (zeros se ainda nao existe)
function linha = pegar_linha(Q, chave, n)
    if isKey(Q, chave)
        linha = Q(chave);
    else
        linha = zeros(1, n + 1);
    end
end


% ==========================================================================
% PERSISTENCIA DA TABELA (salva como chaves+matriz, nao como Map direto,
% porque o Octave nem sempre reconstroi um containers.Map depois de load)
% ==========================================================================

function salvar_Q(Q, arquivo)
    chaves = keys(Q);
    if isempty(chaves)
        valores = [];
    else
        vals_cell = values(Q);
        valores = vertcat(vals_cell{:});
    end
    save(arquivo, 'chaves', 'valores');
end

function Q = carregar_Q(arquivo, num_acoes)
    Q = containers.Map('KeyType', 'char', 'ValueType', 'any');
    try
        dados = load(arquivo);
        if isfield(dados, 'chaves') && isfield(dados, 'valores') && ~isempty(dados.chaves) ...
                && size(dados.valores, 2) == num_acoes + 1
            for i = 1:length(dados.chaves)
                Q(dados.chaves{i}) = dados.valores(i, :);
            end
            disp('Tabela Q carregada de qlearn_tabela_v2.mat');
        else
            disp('Tabela Q vazia ou em formato incompativel - comecando do zero.');
        end
    catch erro
        disp('Nao foi possivel carregar a tabela Q - comecando do zero.');
    end
end


% ==========================================================================
% FUNCOES AUXILIARES (montagem do estado discretizado)
% ==========================================================================

% Acha a escada mais proxima no mesmo andar do Mario e diz se ele esta
% alinhado (0), tem que ir pra direita (1), esquerda (-1) ou nao achou nenhuma (2)
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

% Olha os barris (posicao atual + previsao) e diz o nivel de perigo:
%   0 = sem perigo, 1 = perigo previsto, 2 = perigo iminente
% dir_bin: lado de onde vem o barril perigoso (-1 esquerda, 1 direita, 0 nenhum)
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

% Diz se o foguinho esta perto o suficiente e de qual lado (-1 esquerda, 1 direita)
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
