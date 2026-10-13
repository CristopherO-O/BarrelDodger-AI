% mx, my              -> posição atual do Mario (filtrada pelo Kalman)
% sprite_atual_mario  -> índice/estado do sprite detectado do Mario
% mapa                -> estrutura contendo plataformas, escadas e demais
% bx, by              -> posição atual de cada barril rastreado (vetores)
% bvx, bvy            -> velocidade estimada de cada barril (px/frame)
% bpx, bpy            -> trajetória prevista dos barris (cell arrays)
% fx, fy              -> posição atual do foguinho
% saidas:
% inputs              -> vetor de entrada do NES: [start select up down left right a b]
% Fx, Fy              -> alvo/objetivo atual escolhido (só é preenchido quando a acao escolhida é o controlador)
%
% CHAMADA ESPECIAL DE RESET: Qlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], [])
% Isso avisa o Qlearn que o jogo acabou de ser resetado (morte ou vitoria),
% sem precisar adivinhar isso pela posicao. Se ainda havia uma transicao
% pendente na hora do reset, so pode ter sido por morte (a vitoria ja se
% auto-limpa antes disso acontecer), entao penaliza com RECOMPENSA_MORTE.
%
% Ideia: o Qlearn NAO decide o jogo sozinho do zero. Ele escolhe, a cada frame,
% entre 6 "acoes":
%   1 = sobe
%   2 = desce
%   3 = esquerda
%   4 = direita
%   5 = pulo
%   6 = usar o controlador_mario (a logica pronta que ja sobe escada/desvia de barril)
%
% Ou seja, o Q-learning aprende QUANDO vale a pena deixar o controlador pronto
% jogar por ele e quando vale a pena tomar uma acao "crua". Ele ganha pontos
% por subir de altura (plataformas mais altas = my menor), por desviar de
% barris (pular um barril que estava no caminho), um bônus grande por vencer
% (chegar perto do topo) e uma penalidade por morrer.
function [inputs, Fx, Fy] = Qlearn(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy)

    % ======================================================================
    % CONSTANTES
    % ======================================================================
    NUM_ACOES       = 6;
    ALPHA           = 0.1;    % taxa de aprendizado
    GAMMA           = 0.9;    % desconto do futuro
    EPS_INICIAL     = 0.3;    % chance de exploracao no comeco
    EPS_MIN         = 0.05;   % chance minima de exploracao
    EPS_DECAIMENTO  = 0.9995; % decaimento por frame
    
    PUNICAO_PULO    = -1.0;
    PUNICAO_ESTAGNACAO = -2; % pontos perdidos por frame parado apos o limite
    LIMITE_ESTAGNACAO  = 200;  % frames permitidos sem subir antes de perder pontos

    PESO_ALTURA        = 2;    % pontos por pixel subido
    RECOMPENSA_PULO    = 50.0;    % pontos por desviar de um barril que estava no caminho
    RECOMPENSA_VITORIA = 1000.0;  % bonus por vencer 
    RECOMPENSA_MORTE   = -100.0;  % punicao por morrer

    RECOMPENSA_CONTROLADOR = 0.9;
    PUNICAO_ACAO_CRUA      = -1;

    LIMITE_TELEPORTE = 40;    % px - fallback: se o Mario "pular" mais que isso, foi reset
    Y_VITORIA        = 30;    % px - abaixo disso o Mario venceu a fase

    TOL_ALTURA_ESCADA = 15;   % igual ao usado no controlador_mario
    TOL_ALINHAMENTO   = 3;

    DIST_BARRIL_X = 25;
    DIST_BARRIL_Y = 15;
    HORIZONTE_PREVISAO = 10;  % quantos frames da previsao olhar pra frente

    DIST_FOGUINHO_X = 20;
    DIST_FOGUINHO_Y = 12;

    ARQUIVO_TABELA = 'qlearn_tabela.mat';
    SALVAR_A_CADA  = 500;     % frames

    % ======================================================================
    % ESTADO PERSISTENTE (a tabela Q e o "historico" de 1 frame atras)
    % ======================================================================
    persistent Q total_frames melhor_altura my_anterior;
    persistent estado_anterior acao_anterior pulou_anterior perigo_barril_anterior frames_sem_subir;

    if isempty(Q)
        if exist(ARQUIVO_TABELA, 'file')
            Q = carregar_Q(ARQUIVO_TABELA);
        else
            Q = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end
        frames_sem_subir = 0;
        total_frames           = 0;
        melhor_altura          = NaN;
        my_anterior             = NaN;
        estado_anterior         = '';
        acao_anterior           = 0;
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
            % Ainda havia uma transicao pendente nesse ponto -> so pode ter
            % sido morte (a vitoria ja se auto-limpa antes de chegar aqui).
            if ~isKey(Q, estado_anterior)
                Q(estado_anterior) = zeros(1, NUM_ACOES);
            end
            valores_ant = Q(estado_anterior);
            q_antigo    = valores_ant(acao_anterior);
            valores_ant(acao_anterior) = q_antigo + ALPHA * (RECOMPENSA_MORTE - q_antigo);
            Q(estado_anterior) = valores_ant;
        end

        frames_sem_subir = 0;
        estado_anterior        = '';
        melhor_altura          = NaN;
        my_anterior            = NaN;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
        return;
    end

    % ======================================================================
    % Se o Mario sumiu da tela, nao aprende nesse frame, so segura
    % ======================================================================
    if isnan(mx) || isnan(my) || mx == 0
        return;
    end

    if isnan(melhor_altura)
        melhor_altura = my;
    end

    % ======================================================================
    % Fallback: detecta um "teleporte" de posicao caso algum reset aconteca
    % sem passar pelo sinal explicito acima. Segue a mesma logica: se a
    % posicao anterior ja nao estava em zona de vitoria, so pode ter sido morte.
    % ======================================================================
    if ~isnan(my_anterior) && abs(my - my_anterior) > LIMITE_TELEPORTE

        if ~isempty(estado_anterior) && my_anterior >= Y_VITORIA
            if ~isKey(Q, estado_anterior)
                Q(estado_anterior) = zeros(1, NUM_ACOES);
            end
            valores_ant = Q(estado_anterior);
            q_antigo    = valores_ant(acao_anterior);
            valores_ant(acao_anterior) = q_antigo + ALPHA * (RECOMPENSA_MORTE - q_antigo);
            Q(estado_anterior) = valores_ant;
        end

        frames_sem_subir = 0;
        estado_anterior        = '';
        melhor_altura          = my;
        pulou_anterior         = false;
        perigo_barril_anterior = 0;
    end
    my_anterior = my;

    % ======================================================================
    % Monta o estado atual (discretizado)
    % ======================================================================
    [escada_bin, ~] = avaliar_escada(mx, my, mapa, TOL_ALTURA_ESCADA, TOL_ALINHAMENTO);
    subindo_bin = (sprite_atual_mario == 3);
    [perigo_barril_bin, dir_barril_bin] = avaliar_perigo_barril(mx, my, bx, by, bpx, bpy, ...
        DIST_BARRIL_X, DIST_BARRIL_Y, HORIZONTE_PREVISAO);
    [perigo_fogo_bin, dir_fogo_bin] = avaliar_perigo_foguinho(mx, my, fx, fy, DIST_FOGUINHO_X, DIST_FOGUINHO_Y);

    estado_atual = sprintf('%d|%d|%d|%d|%d|%d', escada_bin, subindo_bin, perigo_barril_bin, dir_barril_bin, perigo_fogo_bin, dir_fogo_bin);
    % ======================================================================
    % Calcula a recompensa da transicao (estado_anterior -> estado_atual)
    % ======================================================================
    if ~isempty(estado_anterior)
        recompensa = 0;

        if acao_anterior == 6
            recompensa = recompensa + RECOMPENSA_CONTROLADOR;
        else
            if perigo_barril_anterior == 0 && perigo_fogo_bin == 0
                recompensa = recompensa + PUNICAO_ACAO_CRUA;
            end
        end
        
        if my < melhor_altura
            ganho = melhor_altura - my;
            melhor_altura = my;
            recompensa = recompensa + ganho * PESO_ALTURA;
            frames_sem_subir = 0; % Bateu recorde! Reseta o cronometro de estagnacao
        else
            frames_sem_subir = frames_sem_subir + 1; % Mais um frame enrolando...
        end

        % Punição se enrolar demais
        if frames_sem_subir > LIMITE_ESTAGNACAO
            recompensa = recompensa + PUNICAO_ESTAGNACAO;
        end

        % Pontos por desviar de um barril que REALMENTE estava no caminho.
        if pulou_anterior 
            if perigo_barril_anterior >= 1 && perigo_barril_bin == 0
                recompensa = recompensa + RECOMPENSA_PULO;
            else
                % Se pulou atoa ou se pulou e continuou em perigo
                recompensa = recompensa + PUNICAO_PULO;
            end
        end

        % Bonus gigante por vencer (chegou perto do topo)
        if my < Y_VITORIA
            recompensa = recompensa + RECOMPENSA_VITORIA;
        end

        % ------------------------------------------------------------
        % Atualiza a tabela Q (Q-learning classico)
        % ------------------------------------------------------------
        if ~isKey(Q, estado_anterior)
            Q(estado_anterior) = zeros(1, NUM_ACOES);
        end
        if ~isKey(Q, estado_atual)
            Q(estado_atual) = zeros(1, NUM_ACOES);
        end

        valores_ant = Q(estado_anterior);
        q_antigo    = valores_ant(acao_anterior);
        max_futuro  = max(Q(estado_atual));

        valores_ant(acao_anterior) = q_antigo + ALPHA * (recompensa + GAMMA * max_futuro - q_antigo);
        Q(estado_anterior) = valores_ant;

        % Se venceu, fecha o episodio aqui e ja salva a tabela imediatamente
        if my < Y_VITORIA
            frames_sem_subir = 0;
            estado_anterior        = '';
            melhor_altura          = NaN;
            pulou_anterior         = false;
            perigo_barril_anterior = 0;
            salvar_Q(Q, ARQUIVO_TABELA);
            return;
        end
    end

    % ======================================================================
    % Escolhe a proxima acao (epsilon-greedy)
    % ======================================================================
    if ~isKey(Q, estado_atual)
        Q(estado_atual) = zeros(1, NUM_ACOES);
    end
    valores = Q(estado_atual);

    epsilon_atual = max(EPS_MIN, EPS_INICIAL * (EPS_DECAIMENTO ^ total_frames));

    if rand() < epsilon_atual
        acao_atual = randi(NUM_ACOES);
    else
        [~, acao_atual] = max(valores);
    end

    % ======================================================================
    % Executa a acao escolhida
    % ======================================================================
    switch acao_atual
        case 1 % sobe
            inputs(3) = 1;
        case 2 % desce
            inputs(4) = 1;
        case 3 % esquerda
            inputs(5) = 1;
        case 4 % direita
            inputs(6) = 1;
        case 5 % pulo
            inputs(7) = 1;
        case 6 % deixa o controlador pronto jogar
            [inputs, Fx, Fy] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
    end

    pulou_anterior         = (inputs(7) == 1);
    perigo_barril_anterior = perigo_barril_bin;

    estado_anterior = estado_atual;
    acao_anterior   = acao_atual;
    total_frames    = total_frames + 1;

    % Salva a tabela de tempos em tempos pra nao perder o aprendizado se fechar o programa
    if mod(total_frames, SALVAR_A_CADA) == 0
        salvar_Q(Q, ARQUIVO_TABELA);
    end

end


% ==========================================================================
% PERSISTENCIA DA TABELA (salva/carrega como chaves+matriz, nao como Map
% direto, porque o Octave nem sempre reconstroi um containers.Map
% corretamente depois de um save/load — foi isso que causou o erro
% "isKey undefined": o Q carregado nao era mais um Map de verdade)
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

function Q = carregar_Q(arquivo)
    Q = containers.Map('KeyType', 'char', 'ValueType', 'any');
    try
        dados = load(arquivo);
        if isfield(dados, 'chaves') && isfield(dados, 'valores') && ~isempty(dados.chaves)
            for i = 1:length(dados.chaves)
                Q(dados.chaves{i}) = dados.valores(i, :);
            end
            disp('Tabela Q carregada de qlearn_tabela.mat');
        else
            disp('Arquivo de tabela Q vazio ou em formato antigo incompativel — comecando do zero.');
        end
    catch erro
        disp('Nao foi possivel carregar a tabela Q (arquivo corrompido ou de formato antigo) — comecando do zero.');
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
%   0 = sem perigo
%   1 = perigo previsto (a previsao mostra um barril chegando perto)
%   2 = perigo iminente (ja esta perto agora)
% dir_bin diz de que lado o barril perigoso esta vindo (-1 esquerda, 1 direita, 0 nenhum)
function [bin, dir_bin] = avaliar_perigo_barril(mx, my, bx, by, bpx, bpy, dist_x, dist_y, horizonte)
    bin = 0;
    dir_bin = 0;

    % Perigo iminente: barril ja esta perto agora
    for i = 1:length(bx)
        if abs(bx(i) - mx) < dist_x && abs(by(i) - my) < dist_y
            bin = 2;
            dir_bin = sign(bx(i) - mx);
            return;
        end
    end

    % Perigo previsto: olha a trajetoria futura de cada barril
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