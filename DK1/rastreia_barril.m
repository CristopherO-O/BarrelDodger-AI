function [barris_x, barris_y, barris_vx, barris_vy, barris_prev_x, barris_prev_y, barris_fant_x, barris_fant_y, barris_id] = rastreia_barril(img, barril, horizonte_frames, mapa)
% Saídas:
%   barris_x/y        — posição filtrada atual (Kalman)
%   barris_vx/vy      — velocidade estimada pelo Kalman (px/frame)
%   barris_prev_x/y   — trajetória prevista "principal" (cell array, 1 linha por barril)
%   barris_fant_x/y   — trajetória "fantasma" (cell array, 1 linha por barril).
%                       Só é preenchida quando a trajetória principal passa
%                       perto de uma escada: representa o caminho alternativo
%                       caso o barril decida descer por ela (o jogo escolhe
%                       isso de forma meio aleatória, então é só um alerta
%                       visual, não uma certeza).
%
% mapa (opcional) — struct vinda da varreduraInicial, com:
%   mapa.plataformas    — máscara binária (mesmo tamanho da imagem do jogo)
%   mapa.escadas_lista   — array de structs com x_centro, y_topo, y_base
%
% Se "mapa" não for passado, a previsão volta a ser o modelo linear antigo
% (compatibilidade com chamadas antigas).
 
    debugar = false;

    % ------------------------------------------------------------------
    % PERSISTENTE
    % ------------------------------------------------------------------
    persistent K_estados K_covs K_max_slots K_frames_sumido;
 
    MAX_SLOTS        = 6;   % máximo de barris simultâneos rastreados
    DIST_ASSOC       = 30;  % px — raio de associação detecção↔tracker
    FRAMES_MAX_SUMIDO = 8;  % frames sem detecção antes de limpar
 
    if isempty(K_estados)
        K_estados      = cell(MAX_SLOTS, 1);   % cada célula: [x; y; vx; vy]
        K_covs         = cell(MAX_SLOTS, 1);   % cada célula: matriz 4×4
        K_frames_sumido = zeros(MAX_SLOTS, 1);
        K_max_slots    = MAX_SLOTS;
    end
 
    if nargin < 3 || isempty(horizonte_frames)
        horizonte_frames = 30;
    end

    if nargin < 4
        mapa = [];
    end
    tem_mapa = ~isempty(mapa) && isfield(mapa, 'plataformas');

    % ------------------------------------------------------------------
    % CONSTANTES DA SIMULAÇÃO FÍSICA (previsão com mapa)
    % ------------------------------------------------------------------
    GRAVIDADE     = 0.8;   % px/frame^2 — aceleração de queda. Ajuste medindo
                            % a variação de vy no barril{1} (frame de queda
                            % capturado na varreduraInicial).
    VY_MAX_QUEDA  = 7;     % px/frame — "velocidade terminal" de queda
    OFFSET_PE     = 5;     % px — distância do centro do barril até a base
                            % (sprite do barril ~10px de altura)
    DIST_ESCADA_X = 6;     % px — tolerância em X pra considerar que o
                            % barril está "sobre" uma escada

 
    % Matrizes do Kalman
    F = [1 0 1 0;   % transição cinemática
         0 1 0 1;
         0 0 1 0;
         0 0 0 1];
    H = [1 0 0 0;   % só observamos X e Y
         0 1 0 0];
    Q = diag([2 2 4 4]);
    R = diag([3, 15]);        % ruído de medição da visão
    I4 = eye(4);
 
    % ==================================================================
    % Detectar barris na imagem atual (codigo antigo, tive que mudar pq o centroid tava dando problema)
    % ==================================================================
    barris_x = [];  barris_y = [];
    barris_vx = []; barris_vy = [];
    barris_id = [];
    barris_prev_x = {};  barris_prev_y = {};
    barris_fant_x = {};  barris_fant_y = {};

    Up = [unique(barril{1})(:); unique(barril{2})(:)];
    Up = unique(Up);
    Up(Up <= 18) = [];

    mascara = false(size(img));
    for i = 1:length(Up)
        mascara = mascara | (img == Up(i));
    end

    se = ones(5, 5);
    mascara = imclose(mascara, se);
    mascara = imfill(mascara, 'holes');
    mascara = bwareaopen(mascara, 30);

    Reg = regionprops(mascara, 'Area', 'BoundingBox', 'Extent');

    det_x = [];
    det_y = [];

    for r = 1:length(Reg)

        if Reg(r).Area > 300
            continue;
        end

        BB = Reg(r).BoundingBox;

        w = BB(3);
        h = BB(4);

        ar = w / h;

        if ar < 0.6 || ar > 1.6
            continue;
        end

        if Reg(r).Extent < 0.68
            continue;
        end

        % ==========================================================
        % Usa o centro da Bounding Box em vez do centroide
        % ==========================================================
        cx = BB(1) + BB(3)/2;
        cy = BB(2) + BB(4)/2;

        det_x(end+1) = cx;
        det_y(end+1) = cy;

        if debugar fprintf("det=(%.2f, %.2f)\n", cx, cy); end

    end
 
    % ==================================================================
    % Predição de todos os slots ativos
    % ==================================================================
    pred_x = nan(MAX_SLOTS, 1);
    pred_y = nan(MAX_SLOTS, 1);
 
    for s = 1:MAX_SLOTS
        if isempty(K_estados{s}),  continue;  end
        K_estados{s} = F * K_estados{s};
        K_covs{s}    = F * K_covs{s} * transpose(F) + Q;
        pred_x(s) = K_estados{s}(1);
        pred_y(s) = K_estados{s}(2);
    end
 
    % ==================================================================

    det_usada   = false(1, length(det_x));
    slot_usado  = false(MAX_SLOTS, 1);
 
    % Para cada slot ativo, busca a detecção mais próxima
    for s = 1:MAX_SLOTS
        if isempty(K_estados{s}),  continue;  end
        if isempty(det_x),         break;     end
 
        dists = sqrt((det_x - pred_x(s)).^2 + (det_y - pred_y(s)).^2);
        [d_min, idx_min] = min(dists);
 
        if d_min < DIST_ASSOC && ~det_usada(idx_min)
            % Update Kalman com a medicao
            z                   = [det_x(idx_min); det_y(idx_min)];
            y_res               = z - H * K_estados{s};
            S                   = H * K_covs{s} * transpose(H) + R;
            K_gain              = K_covs{s} * transpose(H) / S;
            K_estados{s}        = K_estados{s} + K_gain * y_res;
            K_covs{s}           = (I4 - K_gain * H) * K_covs{s};
            K_frames_sumido(s)  = 0;
            det_usada(idx_min)  = true;
            slot_usado(s)       = true;
        else
            % Nenhuma detecção próxima — incrementa contador de sumido
            K_frames_sumido(s) = K_frames_sumido(s) + 1;
            if K_frames_sumido(s) > FRAMES_MAX_SUMIDO
                K_estados{s} = [];  K_covs{s} = [];
                K_frames_sumido(s) = 0;
            end
        end
    end
 
    for d = 1:length(det_x)
        if det_usada(d),  continue;  end
        % Acha slot livre
        slot_livre = find(cellfun(@isempty, K_estados), 1);
        if isempty(slot_livre),  continue;  end
        s = slot_livre;
        K_estados{s} = [det_x(d); det_y(d); 0; 0];
        K_covs{s}    = diag([9 9 25 25]);
        K_frames_sumido(s) = 0;
    end
 
    % ==================================================================
    % Montar saídas e prever trajetoria
    % ==================================================================
    for s = 1:MAX_SLOTS
        if isempty(K_estados{s}),  continue;  end
        if K_frames_sumido(s) > 0, continue;  end  % só exporta slots com hit recente
 
        barris_x(end+1) = K_estados{s}(1);
        barris_y(end+1) = K_estados{s}(2);
        barris_vx(end+1) = K_estados{s}(3);
        barris_vy(end+1) = K_estados{s}(4);
        barris_id(end+1) = s;

        px = zeros(1, horizonte_frames);
        py = zeros(1, horizonte_frames);

        fant_x = [];
        fant_y = [];

        if tem_mapa
            % ==========================================================
            % PREVISAO COM CONSCIENCIA DO MAPA
            % - Enquanto houver plataforma sob o barril -> rola na
            %   horizontal com a vx atual (sem mudar y).
            % - Quando a plataforma "acaba" (buraco/borda) -> entra em
            %   queda livre: aplica gravidade em vy a partir da
            %   velocidade vertical ATUAL do barril (Kalman), nao do
            %   zero, e mantem vx constante.
            % - Quando a queda cruza outra plataforma (ou o chao) mais
            %   abaixo, o y é "encostado" na superficie e ele volta a
            %   rolar com a vx que tinha.
            % - Se sair dos limites do mapa (nao tem mais plataforma
            %   mapeada naquela coluna/linha), para a previsao ali —
            %   nao tem sentido extrapolar pra fora da área mapeada.
            % - Se em algum ponto da rolagem o barril estiver no NIVEL
            %   da plataforma onde uma escada comeca (o topo dela),
            %   gera UMA trajetoria fantasma: uma linha reta descendo
            %   por aquela escada até a plataforma de baixo (y_base),
            %   e para ali. A trajetoria principal continua normal, a
            %   fantasma é só um alerta visual de risco.
            % ==========================================================
            [H_mapa, W_mapa] = size(mapa.plataformas);

            x_sim  = K_estados{s}(1);
            y_sim  = K_estados{s}(2);
            vx_sim = K_estados{s}(3);
            vy_sim = K_estados{s}(4);

            caindo           = ~esta_sobre_plataforma(mapa.plataformas, x_sim, y_sim, OFFSET_PE);
            fantasma_criado  = false;
            n_validos        = horizonte_frames;
            tem_escada_info  = isfield(mapa, 'escadas') && isfield(mapa, 'escadas_lista');

            for t = 1:horizonte_frames

                if ~caindo
                    % rolando sobre a plataforma
                    x_sim  = x_sim + vx_sim;
                    vy_sim = 0;

                    % a plataforma acabou debaixo do novo x? entao na
                    % proxima iteracao ele ja cai (delay de 1 frame,
                    % irrelevante na escala de pixels do jogo)
                    if ~esta_sobre_plataforma(mapa.plataformas, x_sim, y_sim, OFFSET_PE)
                        caindo = true;
                    end
                else
                    % em queda livre — gravidade a partir da vy atual
                    vy_sim = min(vy_sim + GRAVIDADE, VY_MAX_QUEDA);
                    x_sim  = x_sim + vx_sim;
                    y_novo = y_sim + vy_sim;

                    y_solo = encontrar_solo_abaixo(mapa.plataformas, x_sim, y_sim);
                    if ~isempty(y_solo) && (y_novo + OFFSET_PE) >= y_solo
                        % cruzou uma plataforma nesse passo -> encosta
                        y_sim  = y_solo - OFFSET_PE;
                        vy_sim = 0;
                        caindo = false;

                        % No DK as plataformas sao inclinadas — em vez
                        % de chutar que sempre inverte de lado, mede a
                        % inclinação local da plataforma onde aterrissou
                        % (compara a altura um pouco à esquerda e à
                        % direita do ponto) e rola pra onde for "morro"
                        % "abaixo". Se nao conseguir medir (plataforma
                        % plana ali), mantem o sentido que já tinha.
                        dir_sim = direcao_descida(mapa.plataformas, x_sim, y_solo, 6);
                        if dir_sim ~= 0
                            vx_sim = dir_sim * abs(vx_sim);
                        end
                    else
                        y_sim = y_novo;
                    end
                end

                px(t) = x_sim;
                py(t) = y_sim;

                % saiu da área mapeada (caiu fora do mapa, sem chao
                % algum embaixo, ou foi alem da largura do mapa) ->
                % para a previsao aqui, nao extrapola pra fora do mapa
                if x_sim < 1 || x_sim > W_mapa || y_sim < 1 || y_sim > H_mapa
                    n_validos = t;
                    break;
                end

                % ---- trajetoria fantasma da escada (so a primeira) ----
                % Sensor direto na mascara binaria da escada, na altura
                % dos "pes" do barril (mesmo offset usado pra plataforma).
                % Só conta como ameaça quando ele está rolando (nao caindo).
                if ~fantasma_criado && ~caindo && tem_escada_info
                    if tem_escada_abaixo(mapa.escadas, x_sim, y_sim, OFFSET_PE)
                        idx_escada = encontrar_escada_mais_proxima(mapa.escadas_lista, x_sim, DIST_ESCADA_X);
                        if idx_escada > 0
                            fantasma_criado = true;
                            e = mapa.escadas_lista(idx_escada);
                            % linha reta descendo pela escada, parando
                            % exatamente na plataforma de baixo (y_base)
                            fant_x = [x_sim, x_sim];
                            fant_y = [y_sim, e.y_base - OFFSET_PE];
                        end
                    end
                end
            end

            px = px(1:n_validos);
            py = py(1:n_validos);

        else
            % ==========================================================
            % FALLBACK: modelo linear antigo (sem mapa disponivel)
            % ==========================================================
            x_sim = K_estados{s};
            vy_suavizado = 0;

            for t = 1:horizonte_frames
                x_sim = F * x_sim;

                if abs(x_sim(4)) <= 1
                    vy_suavizado = (0.8 * vy_suavizado) + (0.2 * x_sim(4));
                    x_sim(4) = vy_suavizado;
                else
                    vy_suavizado = x_sim(4);
                end

                px(t) = x_sim(1);
                py(t) = x_sim(2);
            end
        end

        barris_prev_x{end+1} = [K_estados{s}(1), px];
        barris_prev_y{end+1} = [K_estados{s}(2), py];
        barris_fant_x{end+1} = fant_x;
        barris_fant_y{end+1} = fant_y;

        if debugar
            fprintf("kal=(%.2f, %.2f) vx=%.2f vy=%.2f\n", ...
            K_estados{s}(1), ...
            K_estados{s}(2), ...
            K_estados{s}(3), ...
            K_estados{s}(4));
        end

    end
end

% ==========================================================================
% FUNÇÕES AUXILIARES — colisão da previsão com o mapa (plataformas/escadas)
% ==========================================================================

function tf = esta_sobre_plataforma(plataformas, x, y, offset_pe)
% Verifica se existe plataforma logo abaixo da posição (x,y), olhando
% uma pequena janela em X pra nao falhar em bordas/serrilhado de 1px.
    [h, w] = size(plataformas);
    xi = min(max(round(x), 1), w);
    yi = min(max(round(y + offset_pe), 1), h);

    x0 = max(xi - 1, 1);
    x1 = min(xi + 1, w);

    tf = any(plataformas(yi, x0:x1));
end

function y_solo = encontrar_solo_abaixo(plataformas, x, y0)
% Varre a coluna x, de y0 para baixo, e devolve a primeira linha onde
% existe plataforma. Devolve [] se nao encontrar nada (ex: buraco/poço
% sem fundo, fora da área mapeada).
    [h, w] = size(plataformas);
    xi = min(max(round(x), 1), w);
    y_ini = max(round(y0), 1);

    y_solo = [];
    coluna = plataformas(y_ini:h, xi);
    idx = find(coluna, 1);
    if ~isempty(idx)
        y_solo = y_ini + idx - 1;
    end
end

function dir = direcao_descida(plataformas, x, y_ref, delta)
% Mede a inclinação local da plataforma em volta de (x, y_ref) — olha
% a altura da superfície um pouco à esquerda (x-delta) e à direita
% (x+delta) — e devolve pra que lado é "morro abaixo":
%   +1 -> desce pra direita (rola pra direita)
%   -1 -> desce pra esquerda (rola pra esquerda)
%    0 -> nao deu pra medir (ou tá plano ali); quem chamou decide o
%         que fazer (normalmente: manter o sentido que já tinha)
    y_esq = encontrar_solo_perto(plataformas, x - delta, y_ref, delta + 2);
    y_dir = encontrar_solo_perto(plataformas, x + delta, y_ref, delta + 2);

    if isempty(y_esq) || isempty(y_dir) || y_esq == y_dir
        dir = 0;
    elseif y_dir > y_esq
        dir = 1;   % superficie mais baixa (y maior) do lado direito
    else
        dir = -1;  % superficie mais baixa do lado esquerdo
    end
end

function y = encontrar_solo_perto(plataformas, x, y_ref, janela)
% Como encontrar_solo_abaixo, mas só procura numa janela pequena em
% volta de y_ref (a superficie da plataforma vizinha nao deve estar
% longe verticalmente do ponto onde o barril aterrissou).
    [h, w] = size(plataformas);
    xi = min(max(round(x), 1), w);
    y0 = max(round(y_ref - janela), 1);
    y1 = min(round(y_ref + janela), h);

    y = [];
    coluna = plataformas(y0:y1, xi);
    idx = find(coluna, 1);
    if ~isempty(idx)
        y = y0 + idx - 1;
    end
end

function tf = tem_escada_abaixo(escadas_mask, x, y, offset_pe)
% Sensor direto na mascara binaria da escada (mapa.escadas), na altura
% dos "pés" do barril — mesma lógica do sensor de plataforma, só que
% checando o pixel de escada em vez de pixel de plataforma. Isso evita
% ficar comparando contra a bounding box (y_topo/y_base) com tolerância,
% que dependia de o offset bater certinho com a detecção da escada.
    [h, w] = size(escadas_mask);
    xi = min(max(round(x), 1), w);
    yi = min(max(round(y + offset_pe), 1), h);

    x0 = max(xi - 1, 1);
    x1 = min(xi + 1, w);

    tf = any(escadas_mask(yi, x0:x1));
end

function idx = encontrar_escada_mais_proxima(escadas_lista, x, dist_x)
% Dado que o sensor já confirmou que tem escada embaixo do barril,
% acha qual entrada da lista (pra pegar o y_base) é essa — a de centro
% em X mais próximo, dentro da tolerância.
    idx = 0;
    if isempty(escadas_lista)
        return;
    end
    melhor_dist = inf;
    for i = 1:length(escadas_lista)
        d = abs(x - escadas_lista(i).x_centro);
        if d <= dist_x && d < melhor_dist
            melhor_dist = d;
            idx = i;
        end
    end
end