function graficos = inicializar_graficos_pc(img_inicial, mapa, MAX_SLOTS_VIS)
    % Tela do jogo (Visão Normal)
    subplot(1, 2, 1);
    graficos.img_plot_pc = imshow(img_inicial);
    title('Visão Normal');

    % Visão do Computador (PC View)
    subplot(1, 2, 2);
    imshow(mapa.plataformas);
    title('PC View');
    hold on;

    % Desenha as escadas uma única vez
    for i = 1:length(mapa.escadas_lista)
        x_escada = mapa.escadas_lista(i).x_centro;
        y_topo   = mapa.escadas_lista(i).y_topo;
        y_base   = mapa.escadas_lista(i).y_base;
        plot([x_escada, x_escada], [y_topo, y_base], 'g-', 'LineWidth', 2);
        y_meio = (y_topo + y_base) / 2;
        text(x_escada + 4, y_meio, num2str(i), 'Color', 'y', 'FontSize', 10, 'FontWeight', 'bold');
    end

    % Cria os handles (referências) dos plots vazios
    graficos.mario_plot = plot(NaN, NaN, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);

    graficos.barris_plot = plot(NaN, NaN, 'o', ...
        'MarkerEdgeColor', [1 0.5 0], 'MarkerFaceColor', [1 0.5 0], 'MarkerSize', 7);

    graficos.barris_id_text = zeros(MAX_SLOTS_VIS, 1);
    for s = 1:MAX_SLOTS_VIS
        graficos.barris_id_text(s) = text(NaN, NaN, '', ...
            'Color', 'w', 'FontSize', 9, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'BackgroundColor', [0 0 0]);
    end

    % Trajetória prevista dos barris
    graficos.prev_plots = zeros(MAX_SLOTS_VIS, 1); 
    for s = 1:MAX_SLOTS_VIS
        graficos.prev_plots(s) = plot(NaN, NaN, '--', 'Color', [1 0.65 0], 'LineWidth', 1.2);
    end

    % Trajetória "fantasma" — alerta de possível queda pela escada
    graficos.fant_plots = zeros(MAX_SLOTS_VIS, 1);
    for s = 1:MAX_SLOTS_VIS
        graficos.fant_plots(s) = plot(NaN, NaN, ':', 'Color', [0.2 0.85 1], 'LineWidth', 1.6);
    end

    % Ponto de impacto previsto 
    graficos.impacto_plot = plot(NaN, NaN, 'x', ...
        'Color', [1 0.2 0.2], 'MarkerSize', 10, 'LineWidth', 2);

    % Foguinho
    graficos.foguinho_plot = plot(NaN, NaN, 'o', ...
        'MarkerEdgeColor', 'y', 'MarkerFaceColor', 'y', 'MarkerSize', 6);

    % Texto com o estado atual do Mario
    graficos.texto_estado = text(5, 12, 'ANDANDO', 'Color', 'w', ...
        'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [0 0 0]);

    hold off;
end