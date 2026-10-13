function [barris_x, barris_y, barris_vx, barris_vy, barris_prev_x, barris_prev_y] = rastreia_barril(img, barril, horizonte_frames)
% Saídas:
%   barris_x/y        — posição filtrada atual (Kalman)
%   barris_vx/vy      — velocidade estimada pelo Kalman (px/frame)
%   barris_prev_x/y   — trajetória prevista (cell array, 1 linha por barril)
 
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
    barris_prev_x = {};  barris_prev_y = {};

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
        K_covs{s}    = F * K_covs{s} * F' + Q;
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
            S                   = H * K_covs{s} * H' + R;
            K_gain              = K_covs{s} * H' / S;
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
 
        % Previsao — simula F
        x_sim = K_estados{s};
        px = zeros(1, horizonte_frames);
        py = zeros(1, horizonte_frames);
        
        vy_suavizado = 0;
        
        for t = 1:horizonte_frames
            % Executa a matriz de transição do Kalman normalmente
            x_sim = F * x_sim;
            
            % Se a velocidade for pequena o valor é fragmentado para deixar mais suave os degraus
            % Se for uma queda livre de escada, passa direto.
            if abs(x_sim(4)) <= 1
                vy_suavizado = (0.8 * vy_suavizado) + (0.2 * x_sim(4));
                x_sim(4) = vy_suavizado; 
            else
                % Queda rápida nao suaviza
                vy_suavizado = x_sim(4); 
            end
            
            px(t) = x_sim(1);
            py(t) = x_sim(2);
        end
        
        barris_prev_x{end+1} = px;
        barris_prev_y{end+1} = py;

        if debugar
            fprintf("kal=(%.2f, %.2f) vx=%.2f vy=%.2f\n", ...
            K_estados{s}(1), ...
            K_estados{s}(2), ...
            K_estados{s}(3), ...
            K_estados{s}(4));
        end

    end
end
