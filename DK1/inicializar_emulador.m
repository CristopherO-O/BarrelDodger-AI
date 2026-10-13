function [jogo, mem_inicial] = inicializar_emulador(rom_name)

    jogo = load_rom(rom_name);
    fprintf('ROM iniciada com sucesso: %s\n', rom_name);

    % Sequência de Boot específica do Donkey Kong
    jogo.step(70);
    jogo.set_input([1 0 0 0 0 0 0 0]);
    % [start select up down left right a b]
    jogo.step(50);
    jogo.set_input([0 0 0 0 0 0 0 0]);
    jogo.step(450); % Espera a animação de introdução terminar

    % Salva o estado ideal para fazer restart
    mem_inicial = jogo.get_state();
end