function atualizar_pc_view(handles, imc, frames_sem_mario, limite_sumido, mx, my, bx, by, barris_id, bpx, bpy, bfx, bfy, fx, fy, estado_atual, MAX_SLOTS_VIS)
    % Atualiza a imagem de fundo
    set(handles.img_plot_pc, 'CData', imc);

    % Atualiza Mario
    if frames_sem_mario < limite_sumido
        set(handles.mario_plot, 'XData', mx, 'YData', my);
    else
        set(handles.mario_plot, 'XData', NaN, 'YData', NaN);
    end

    % Atualiza Barris — posição atual
    if ~isempty(bx)
        set(handles.barris_plot, 'XData', bx, 'YData', by);
    else
        set(handles.barris_plot, 'XData', NaN, 'YData', NaN);
    end

    % Atualiza a etiqueta de cada barril pelo ID persistente do tracker
    for s = 1:MAX_SLOTS_VIS
        idx = find(barris_id == s, 1);
        if ~isempty(idx)
            set(handles.barris_id_text(s), ...
                'Position', [bx(idx), by(idx) - 8, 0], ...
                'String', num2str(s));
        else
            set(handles.barris_id_text(s), 'Position', [NaN, NaN, 0]);
        end
    end

    % Atualiza Trajetórias previstas (principal + fantasma da escada)
    imp_x_all = [];
    imp_y_all = [];
    for s = 1:MAX_SLOTS_VIS
        idx = find(barris_id == s, 1);
        if ~isempty(idx) && idx <= length(bpx) && ~isempty(bpx{idx})
            set(handles.prev_plots(s), 'XData', bpx{idx}, 'YData', bpy{idx});
            % Ponto de impacto = último ponto da trajetória
            imp_x_all(end+1) = bpx{idx}(end);
            imp_y_all(end+1) = bpy{idx}(end);
        else
            set(handles.prev_plots(s), 'XData', NaN, 'YData', NaN);
        end

        if ~isempty(idx) && idx <= length(bfx) && ~isempty(bfx{idx})
            set(handles.fant_plots(s), 'XData', bfx{idx}, 'YData', bfy{idx});
        else
            set(handles.fant_plots(s), 'XData', NaN, 'YData', NaN);
        end
    end
    
    % Atualiza Ponto de Impacto
    if ~isempty(imp_x_all)
        set(handles.impacto_plot, 'XData', imp_x_all, 'YData', imp_y_all);
    else
        set(handles.impacto_plot, 'XData', NaN, 'YData', NaN);
    end

    % Atualiza Foguinho
    if ~isempty(fx)
        set(handles.foguinho_plot, 'XData', fx, 'YData', fy);
    else
        set(handles.foguinho_plot, 'XData', NaN, 'YData', NaN);
    end

    % Atualiza Estado atual do Mario
    set(handles.texto_estado, 'String', estado_atual);

    drawnow;
end