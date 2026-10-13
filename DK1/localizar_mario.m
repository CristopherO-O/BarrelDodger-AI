function [x, y, sprite, scr] = localizar_mario(img, mc)
    Up = [unique(mc{1})(:); unique(mc{3})(:); unique(mc{4})(:); unique(mc{5})(:)];
    Up = unique(Up);
    Up(Up <= 18) = []; % o bckground é 16 isso filtra ele e outros ruidos pois a borda do mario é 19

    saida = 0;
    [lp, cp] = size(mc{1});
    se = ones(round(sqrt(lp)), round(sqrt(cp)));  
    for i = 1:length(Up)
        saida = saida + imdilate(img == Up(i), se); 
    end
    ms=max(saida(:));
    if ms == 0  % Se não achou nenhuma das cores do Mario
        x = 0; y = 0; scr = 0;
        return;
    end
    saida=imclose(saida==ms, ones(5));
    Reg=regionprops(saida);

    melhor_scr = -1;
    melhor_x = 0;
    melhor_y = 0;
    for k = 1:length(mc)
        pad = mc{k};
        [lp_k, cp_k] = size(pad); %as imagens tem diferença de tamanho
        for i = 1:length(Reg)
            BB = Reg(i).BoundingBox;
            BB(1:2) = BB(1:2) - [cp_k, lp_k] / 2;
            BB(3:4) = [cp_k, lp_k] * 2;
            cand = imcrop(img, BB);
            if size(cand, 1) >= lp_k && size(cand, 2) >= cp_k
                corr = normxcorr2(pad, cand);
                sc = max(corr(:));
                
                if sc > melhor_scr
                    melhor_scr = sc;
                    sprite = k;
                    % Encontra onde está o pico de similaridade na matriz
                    [y_peak, x_peak] = find(corr == sc, 1);
                    
                    melhor_x = BB(1) + x_peak - (cp_k / 2); %centroid dava muita variação então eu corrigi para x e y
                    melhor_y = BB(2) + y_peak - (lp_k / 2);

                end
            end
        end
    end

    x = melhor_x;
    y = melhor_y;
    scr = melhor_scr;
end
