function [foguinho_x, foguinho_y] = localizar_foguinho(img)
    foguinho_x = [];
    foguinho_y = [];
    mascara = (img == 220);

    if ~any(mascara(:))
        return;
    end

    mascara = imclose(mascara, ones(3));

    area_minima = 10; % Remove ruido
    mascara = bwareaopen(mascara, area_minima);

    Reg = regionprops(mascara, 'Centroid');

    for i = 1:length(Reg)
        foguinho_x(end+1) = Reg(i).Centroid(1);
        foguinho_y(end+1) = Reg(i).Centroid(2);
    end
end