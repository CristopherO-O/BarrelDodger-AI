% Existem tres estados principais: ANDANDO, PULANDO, NA_ESCADA
% ANDANDO -> PULANDO
%   Nao existe sprite diferente pra pular, entao a deteccao usa a
%   variacao vertical vy da posicao d Mario frame a frame. O degrau
%   das plataformas gera uma variacao pequena 1 px, mas o pulo tem uma
%   trajetoria fixa e bem mais brusca, entao um |vy| acima de um limiar
%   indica que ele saiu d chao.
%
% PULANDO -> ANDANDO
%   Como o pulo sempre tem a mesma altura/duracao, ele sobe e depois cai.
%   Quando a queda vy positivo para abruptamente, o Mario aterrissou.
%   so comeca a procurar isso depois de alguns frames no ar, pra nao
%   confundir com o instante inicial d pulo.
%
% ANDANDO -> NA_ESCADA
%   mc 3 e mc 4 gerados na varreduraInicial sao os sprites de Mario
%   de costas, subindo/na escada. Se localizar_mario retornar um
%   desses indices como melhor correlacao com score alto o bastante,
%   o Mario esta na escada.
%
% NA_ESCADA -> ANDANDO
%   - Subindo: mc 5 e o sprite exato d topo da escada quase sem
%     variacao de pixel a pixel, entao uma correlacao MUITO alta com
%     ele indica que chegou ao topo.
%   - Descendo: nao existe sprite de fim da escada pra baixo. Como na
%     escada o Mario so se move verticalmente vx ~ 0 o tempo todo,
%     quem avisa que ele chegou na base e a velocidade VERTICAL parar
%     de variar ~0 depois de estar descendo.
% =====================================================================

classdef EstadoMario < handle
    properties
        EstadoAtual      = 'ANDANDO'   % ANDANDO, PULANDO, NA_ESCADA
        FramesNoAr       = 0           % contador de frames no ar (pulo)
        DirecaoEscada    = ''          % 'subindo' ou 'descendo'

        % ---- ultima leitura (pra calcular velocidade) ----
        x_ant            = NaN
        y_ant            = NaN
        vx               = 0
        vy               = 0

        % ---- contador de confirmacao (evita flicker por ruido) ----
        contagem_parado  = 0

        % =========================================================================================================
        LIMIAR_VY_PULO        = 3.0   % px/frame -> acima disso = comecou a subir/cair pulo
        LIMIAR_VY_PARADO      = 0.6   % px/frame -> abaixo disso = parou verticalmente
        FRAMES_MIN_NO_AR      = 3     % nao procura aterrissagem nos primeiros frames d pulo ele sobe antes de cair
        FRAMES_CONFIRMA_POUSO = 2     % frames seguidos parado pra confirmar aterrissagem
        FRAMES_CONFIRMA_BASE  = 3     % frames seguidos parado pra confirmar base da escada

        SPRITES_ESCADA        = [3 4] % indices de mc que sao sprites de escada subindo
        SPRITE_TOPO_ESCADA    = 5     % indice de mc = topo da escada
        SCR_MIN_ESCADA        = 0.55  % correlacao minima p/ aceitar sprite de escada
        SCR_MIN_TOPO          = 0.85  % correlacao minima alta p/ aceitar chegou no topo
    end

    methods
        function atualizar(obj, x, y, sprite, scr)
            % Chamar por frame, com x, y, sprite, scr vindos de
            % localizar_mario. Atualiza a maquina de estados.
            if isnan(obj.x_ant) || isnan(obj.y_ant)
                obj.vx = 0;
                obj.vy = 0;
            else
                obj.vx = x - obj.x_ant;
                obj.vy = y - obj.y_ant;   % y cresce p/ baixo na imagem
            end

            switch obj.EstadoAtual
                case 'ANDANDO'
                    obj.checarEntrada(sprite, scr);

                case 'PULANDO'
                    obj.FramesNoAr = obj.FramesNoAr + 1;
                    obj.checarAterrissagem();

                case 'NA_ESCADA'
                    obj.atualizarDirecaoEscada();
                    obj.checarSaidaEscada(sprite, scr);
            end

            obj.x_ant = x;
            obj.y_ant = y;
        end

        function reiniciar(obj)
            % Chamar quando o Mario morre / o jogo reseta, pra nao
            % carregar estado de uma vida pra outra.
            obj.EstadoAtual     = 'ANDANDO';
            obj.FramesNoAr      = 0;
            obj.DirecaoEscada   = '';
            obj.x_ant           = NaN;
            obj.y_ant           = NaN;
            obj.vx              = 0;
            obj.vy              = 0;
            obj.contagem_parado = 0;
        end

        function mudarPara(obj, novoEstado)
            % Transicao manual (debug / casos especiais)
            obj.EstadoAtual     = novoEstado;
            obj.FramesNoAr       = 0;
            obj.contagem_parado = 0;
        end
    end

    methods (Access = private)
        function checarEntrada(obj, sprite, scr)
            % Prioridade pra escada (sprite e mais confiavel que vy).
            % Se nao bater com escada, olha a variacao vertical p/ pulo.
            if any(obj.SPRITES_ESCADA == sprite) && scr > obj.SCR_MIN_ESCADA
                obj.EstadoAtual     = 'NA_ESCADA';
                obj.DirecaoEscada   = '';
                obj.contagem_parado = 0;

            elseif abs(obj.vy) > obj.LIMIAR_VY_PULO
                obj.EstadoAtual     = 'PULANDO';
                obj.FramesNoAr      = 0;
                obj.contagem_parado = 0;
            end
        end

        function checarAterrissagem(obj)
            if obj.FramesNoAr < obj.FRAMES_MIN_NO_AR
                return; % ainda subindo, nao faz sentido procurar pouso
            end

            if abs(obj.vy) < obj.LIMIAR_VY_PARADO
                obj.contagem_parado = obj.contagem_parado + 1;
                if obj.contagem_parado >= obj.FRAMES_CONFIRMA_POUSO
                    obj.EstadoAtual     = 'ANDANDO';
                    obj.FramesNoAr      = 0;
                    obj.contagem_parado = 0;
                end
            else
                obj.contagem_parado = 0;
            end
        end

        function atualizarDirecaoEscada(obj)
            % So troca de direcao com um sinal "forte" de vy, pra nao
            % oscilar com ruido perto de zero.
            if obj.vy < -0.3
                obj.DirecaoEscada = 'subindo';
            elseif obj.vy > 0.3
                obj.DirecaoEscada = 'descendo';
            end
        end

        function checarSaidaEscada(obj, sprite, scr)
            % Caso 1: chegou no topo -> correlacao muito alta com mc{5}
            if sprite == obj.SPRITE_TOPO_ESCADA && scr > obj.SCR_MIN_TOPO
                obj.EstadoAtual     = 'ANDANDO';
                obj.DirecaoEscada   = '';
                obj.contagem_parado = 0;
                return;
            end

            % Caso 2: chegou na base (descendo) -> nao tem sprite de
            % fim, entao usa a velocidade VERTICAL parar de variar.
            if strcmp(obj.DirecaoEscada, 'descendo') && abs(obj.vy) < obj.LIMIAR_VY_PARADO
                obj.contagem_parado = obj.contagem_parado + 1;
                if obj.contagem_parado >= obj.FRAMES_CONFIRMA_BASE
                    obj.EstadoAtual     = 'ANDANDO';
                    obj.DirecaoEscada   = '';
                    obj.contagem_parado = 0;
                end
            else
                obj.contagem_parado = 0;
            end
        end
    end
end