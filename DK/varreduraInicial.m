function [mapa, mc, inimigos] = varreduraInicial(jogo)
    im = jogo.get_image();
    img = rgb2gray(im);

    R = im(:,:,1);
    G = im(:,:,2);
    B = im(:,:,3);

    % =========================================================================================
    area_min_plat = 40;
    area_min_escada = 80;

    plat_raw = (R == 208 & G == 20 & B == 116);
    escada_raw = (R == 28 & G == 194 & B == 234);

    plataforma = bwareaopen(plat_raw, area_min_plat); %plataforma foi facil

    %escada precisou fechar pra checar a area
    se = strel('rectangle', [5, 2]);
    escada_temp = imclose(escada_raw, se);
    escada_temp = imfill(escada_temp, 'holes');
    escada = bwareaopen(escada_temp, area_min_escada);
    escada(200:220, 1:80) = 0; %remove o barril no canto que tem a mesma cor da escada

    %lista todas as escadas
    stats = regionprops(escada, 'BoundingBox', 'Centroid');
    escadas_l = [];

    for i = 1:length(stats)
        bb = stats(i).BoundingBox;

        escadas_l(i).x_centro = bb(1) + (bb(3) / 2);
        
        escadas_l(i).y_topo = bb(2);
        escadas_l(i).y_base = bb(2) + bb(4);
        
        fprintf('Escada %d mapeada: X=%.1f | Y de %.1f ate %.1f\n', i, escadas_l(i).x_centro, escadas_l(i).y_topo, escadas_l(i).y_base);
    end

    mapa.escadas_lista = escadas_l;


    mapa.plataformas = plataforma;
    mapa.escadas = escada;

    save('mapa_dk_level1.mat', 'mapa');
    disp('Arquivo "mapa_dk_level1.mat" gerado com sucesso!');

    % =========================================================================================
    mc{1} = img(201:207, 51:62);     % Original
    mc{2} = mc{1}(:, end:-1:1);      % Invertida

    jogo.set_input([0 0 0 0 0 1 0 0]);
    jogo.step(240);
    jogo.set_input([0 0 0 0 0 0 0 0]);
    jogo.step(2);
    jogo.set_input([0 0 1 0 0 0 0 0]);
    im = jogo.get_image();
    img = rgb2gray(im);
    barril{1} = img(204:213, 50:64); %barril caindo

    jogo.step(3);
    im = jogo.get_image();
    img = rgb2gray(im);
    mc{3} = img(196:211, 198:210);  %subindo escada
    
    jogo.step(50);

    im = jogo.get_image();
    img = rgb2gray(im);
    mc{4} = img(180:191, 197:212); %terminando escada 1

    jogo.step(25);

    im = jogo.get_image();
    img = rgb2gray(im);
    mc{5} = img(174:188, 197:212); %terminando escada 2

    save('mc_template.mat', 'mc');
    disp('Arquivo "mc_template.mat" gerado com sucesso!');

    jogo.step(30);
    im = jogo.get_image();
    img = rgb2gray(im);
    barril{2} = img(57:66, 160:171); %barril rolando
    foguinho = img(201:216, 70:83);
    inimigos.barril = barril;
    inimigos.foguinho = foguinho;

    save('inimigos_template.mat', 'inimigos');
    disp('Arquivo "inimigos_template.mat" gerado com sucesso!');


end