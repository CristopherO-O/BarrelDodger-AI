% mx, my              -> posição atual do Mario (filtrada pelo Kalman)
% sprite_atual_mario  -> índice/estado do sprite detectado do Mario
% mapa                -> estrutura contendo plataformas, escadas e demais
% bx, by              -> posição atual de cada barril rastreado(vetores, um elemento por barril)
% bvx, bvy            -> velocidade estimada de cada barril (px/frame)
% bpx, bpy            -> trajetória prevista dos barris cell arrays onde: bpx{i}(t) = posição X futura | bpy{i}(t) = posição Y futura
% fx, fy              -> posição atual do foguinho
% saidas:
% inputs              -> vetor de entrada do NES: [start select up down left right a b]
% Fx, Fy              -> alvo/objetivo atual escolhido

% sobre sprite_atual_mario se for:
% 1 : rosto pra a direita
% 2 : rosto para a esquerda
% 3 : subindo escada
% 5 : terminou de subir a escada (de costas)
function [inputs, Fx, Fy] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);

    % ======================================================================
    % ESTADO PERSISTENTE (maquina de estado simples, sem aprendizado)
    % ======================================================================
    persistent estado escada_alvo my_anterior contagem_parado;

    if isempty(estado)
        estado          = 'ANDANDO';   % 'ANDANDO' ou 'SUBINDO'
        escada_alvo     = [];
        my_anterior     = NaN;
        contagem_parado = 0;
    end

    % ======================================================================
    % CONSTANTES (ajustes)
    % ======================================================================
    TOL_ALTURA       = 15;  % px - quao perto o Mario tem que estar da base da escada pra ela contar como "mesmo andar"
    TOL_ALINHAMENTO  = 2;   % px - quao alinhado com o centro da escada pra comecar a subir

    FRAMES_PARADO    = 5;   % quantos frames com y parado pra considerar que a subida acabou

    DIST_BARRIL_X = 25; % px - distancia horizontal pra considerar o barril "no caminho"
    DIST_BARRIL_Y = 15; % px - distancia vertical (mesma altura/andar)

    inputs = zeros(1, 8);
    Fx = NaN;
    Fy = NaN;

    % ======================================================================
    % Se o Mario sumiu da tela, sobe
    % ======================================================================
    if isnan(mx) || isnan(my) || mx == 0
        inputs(3) = 1;
        return;
    end

    % ======================================================================
    % MAQUINA DE ESTADO
    % ======================================================================
    switch estado

        % ------------------------------------------------------------
        case 'ANDANDO'
        % ------------------------------------------------------------

            % Procura escadas que estao na mesma altura que o Mario (base da escada = andar atual)
            idx_validas = [];
            for i = 1:length(mapa.escadas_lista)
                e = mapa.escadas_lista(i);
                if abs(my - e.y_base) <= TOL_ALTURA
                    idx_validas(end+1) = i;
                end
            end

            if isempty(idx_validas)
                % Nenhuma escada no andar atual -> continua andando pra direita (padrao do nivel)
                escada_alvo = [];
                inputs(6) = 1; % direita
            else
                % Acha a escada mais proxima
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

                Fx = escada_alvo.x_centro;
                Fy = escada_alvo.y_topo;

                dx = escada_alvo.x_centro - mx;

                if abs(dx) <= TOL_ALINHAMENTO
                    % Alinhado com a escada -> comeca a subir
                    estado          = 'SUBINDO';
                    my_anterior     = my;
                    contagem_parado = 0;
                    inputs(3) = 1; % up
                elseif dx > 0
                    inputs(6) = 1; % direita
                else
                    inputs(5) = 1; % esquerda
                end
            end

            % Desvia de barril no caminho (so enquanto ainda estiver andando)
            if strcmp(estado, 'ANDANDO')
                for i = 1:length(bx)
                    if abs(bx(i) - mx) < DIST_BARRIL_X && abs(by(i) - my) < DIST_BARRIL_Y
                        inputs(7) = 1; % pula (A)
                        break;
                    end
                end
            end

        % ------------------------------------------------------------
        case 'SUBINDO'
        % ------------------------------------------------------------

            inputs(3) = 1; % continua subindo sem parar

            if ~isempty(escada_alvo)
                Fx = escada_alvo.x_centro;
                Fy = escada_alvo.y_topo;
            end

            terminou = false;

            % Metodo 3: o Y parou de subir
            if ~isnan(my_anterior) && abs(my - my_anterior) < 0.5
                contagem_parado = contagem_parado + 1;
            else
                contagem_parado = 0;
            end
            if contagem_parado >= FRAMES_PARADO
                terminou = true;
            end


            my_anterior = my;

            if terminou
                estado          = 'ANDANDO';
                escada_alvo     = [];
                contagem_parado = 0;
                inputs(3) = 0;
            end

    end

end