
function view = PCView(acao, varargin)
% PCView - Modulo de visualizacao do Donkey Kong.
%
% Acoes:
%   view = PCView('init', fig, imagem, mapa, habilitado)
%   view = PCView('update', view, dados)
%   PCView('reset', view)
%
% O modulo nao controla o jogo nem calcula as deteccoes.
%
% Dados esperados em 'update':
%   imc, img, mx, my
%   frames_sem_mario, limite_sumido
%   bx, by
%   bpx, bpy       - trajetorias principais previstas
%   bfx, bfy       - trajetorias alternativas pelas escadas
%   fx, fy         - posicao do foguinho

    switch lower(acao)
        case 'init'
            view = inicializar_view(varargin{:});

        case 'update'
            view = varargin{1};
            dados = varargin{2};
            atualizar_view(view, dados);

        case 'reset'
            view = varargin{1};
            limpar_view(view);

        otherwise
            error('PCView: acao invalida: %s', acao);
    end
end


function view = inicializar_view(fig, imagem, mapa, habilitado)

    view = struct();
    view.habilitado = habilitado;
    view.fig = fig;

    if habilitado
        figure(fig);

        % Visao normal do jogo.
        subplot(1, 2, 1);
        view.img_plot_pc = imshow(imagem);
        title('Visao Normal');

        % Visao processada pelo computador.
        subplot(1, 2, 2);
        imshow(mapa.plataformas);
        title('PC View - Kalman e previsao fisica');
        hold on;

        % Escadas.
        if isfield(mapa, 'escadas_lista')
            for i = 1:length(mapa.escadas_lista)
                x = mapa.escadas_lista(i).x_centro;
                yt = mapa.escadas_lista(i).y_topo;
                yb = mapa.escadas_lista(i).y_base;

                plot([x, x], [yt, yb], 'g-', ...
                    'LineWidth', 2);

                ym = (yt + yb) / 2;
                text(x + 4, ym, num2str(i), ...
                    'Color', 'y', ...
                    'FontSize', 10, ...
                    'FontWeight', 'bold');
            end
        end

        % Mario.
        view.mario_plot = plot(NaN, NaN, 'ro', ...
            'MarkerFaceColor', 'r', ...
            'MarkerSize', 8);

        % Barris detectados.
        view.barris_plot = plot(NaN, NaN, 'o', ...
            'MarkerEdgeColor', [1 0.5 0], ...
            'MarkerFaceColor', [1 0.5 0], ...
            'MarkerSize', 7);

        % Numero maximo de slots de rastreamento.
        view.max_slots = 6;

        % Trajetorias principais: previsao fisica.
        view.prev_plots = zeros(view.max_slots, 1);

        for s = 1:view.max_slots
            view.prev_plots(s) = plot(NaN, NaN, '--', ...
                'Color', [1 0.65 0], ...
                'LineWidth', 1.5);
        end

        % Trajetorias alternativas: caminho pelas escadas.
        view.fant_plots = zeros(view.max_slots, 1);

        for s = 1:view.max_slots
            view.fant_plots(s) = plot(NaN, NaN, ':', ...
                'Color', [0 0.8 1], ...
                'LineWidth', 2);
        end

        % Pontos finais das trajetorias principais.
        view.impacto_plot = plot(NaN, NaN, 'x', ...
            'Color', [1 0.2 0.2], ...
            'MarkerSize', 10, ...
            'LineWidth', 2);

        % Foguinho.
        view.foguinho_plot = plot(NaN, NaN, 'o', ...
            'MarkerEdgeColor', 'y', ...
            'MarkerFaceColor', 'y', ...
            'MarkerSize', 6);

    else
        figure(fig);
        view.img_plot = imshow(imagem);
    end
end


function atualizar_view(view, d)

    if view.habilitado

        % Imagem original.
        set(view.img_plot_pc, 'CData', d.imc);

        % Mario.
        if d.frames_sem_mario < d.limite_sumido
            set(view.mario_plot, ...
                'XData', d.mx, ...
                'YData', d.my);
        else
            set(view.mario_plot, ...
                'XData', NaN, ...
                'YData', NaN);
        end

        % Barris detectados.
        if ~isempty(d.bx)
            set(view.barris_plot, ...
                'XData', d.bx, ...
                'YData', d.by);
        else
            set(view.barris_plot, ...
                'XData', NaN, ...
                'YData', NaN);
        end

        % Trajetorias previstas e pontos finais.
        imp_x = [];
        imp_y = [];

        for s = 1:view.max_slots

            % -----------------------------------------
            % Trajetoria principal: gravidade e mapa.
            % -----------------------------------------
            if isfield(d, 'bpx') && ...
               isfield(d, 'bpy') && ...
               s <= length(d.bpx) && ...
               s <= length(d.bpy) && ...
               ~isempty(d.bpx{s}) && ...
               ~isempty(d.bpy{s})

                px = d.bpx{s};
                py = d.bpy{s};

                set(view.prev_plots(s), ...
                    'XData', px, ...
                    'YData', py);

                % Marca o ponto final da previsao.
                imp_x(end + 1) = px(end);
                imp_y(end + 1) = py(end);

            else
                set(view.prev_plots(s), ...
                    'XData', NaN, ...
                    'YData', NaN);
            end

            % -----------------------------------------
            % Trajetoria alternativa por escadas.
            % -----------------------------------------
            if isfield(d, 'bfx') && ...
               isfield(d, 'bfy') && ...
               s <= length(d.bfx) && ...
               s <= length(d.bfy) && ...
               ~isempty(d.bfx{s}) && ...
               ~isempty(d.bfy{s})

                fx_alt = d.bfx{s};
                fy_alt = d.bfy{s};

                set(view.fant_plots(s), ...
                    'XData', fx_alt, ...
                    'YData', fy_alt);

            else
                set(view.fant_plots(s), ...
                    'XData', NaN, ...
                    'YData', NaN);
            end
        end

        % Atualiza os pontos finais das previsoes principais.
        if ~isempty(imp_x)
            set(view.impacto_plot, ...
                'XData', imp_x, ...
                'YData', imp_y);
        else
            set(view.impacto_plot, ...
                'XData', NaN, ...
                'YData', NaN);
        end

        % Foguinho.
        if isfield(d, 'fx') && ...
           isfield(d, 'fy') && ...
           ~isempty(d.fx) && ...
           ~isempty(d.fy)

            set(view.foguinho_plot, ...
                'XData', d.fx, ...
                'YData', d.fy);
        else
            set(view.foguinho_plot, ...
                'XData', NaN, ...
                'YData', NaN);
        end

    else
        % Sem PC View, apenas a imagem.
        set(view.img_plot, 'CData', d.img);
    end

    drawnow;
end


function limpar_view(view)
% Limpa os elementos dinamicos ao reiniciar uma run.

    if ~view.habilitado
        return;
    end

    set(view.mario_plot, ...
        'XData', NaN, 'YData', NaN);

    set(view.barris_plot, ...
        'XData', NaN, 'YData', NaN);

    for s = 1:view.max_slots

        % Limpa previsao fisica.
        set(view.prev_plots(s), ...
            'XData', NaN, 'YData', NaN);

        % Limpa previsao alternativa.
        set(view.fant_plots(s), ...
            'XData', NaN, 'YData', NaN);
    end

    set(view.impacto_plot, ...
        'XData', NaN, 'YData', NaN);

    set(view.foguinho_plot, ...
        'XData', NaN, 'YData', NaN);
end
