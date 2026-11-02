classdef RetroGame < handle
  %RetroGame  Objeto para controlar um jogo via Libretro.
  % Botoes: [start, select, up, down, left, right, A, B, C, X, Y, Z, L, R]

  properties (SetAccess = private)
    id
    system_name
    core_path
    rom_path
  end

  methods
    function obj = RetroGame(id, system_name, core_path, rom_path)
      obj.id = id;
      obj.system_name = system_name;
      obj.core_path = core_path;
      obj.rom_path = rom_path;
    end

    function delete(obj)
      if ~isempty(obj.id)
        try
          retro_games('close', obj.id);
        catch
        end
      end
    end

    function step(obj, n)
      if nargin < 2, n = 1; end
      retro_games('step', obj.id, uint64(n));
    end

    function set_input(obj, vec, player)
      if nargin < 3, player = 1; end
      player = uint64(player);
      vec = vec(:).';
      if numel(vec) > 14
        error('RetroGame.set_input: vetor de botoes deve ter no maximo 14 entradas.');
      end
      full = zeros(1,14);
      full(1:numel(vec)) = vec;
      retro_games('set_input', obj.id, player, full);
    end

    function img = get_image(obj)
      img = retro_games('get_image', obj.id);
    end

    function s = get_state(obj)
      s = retro_games('get_state', obj.id);
    end

    function set_state(obj, s)
      retro_games('set_state', obj.id, s);
    end

    function close(obj)
      retro_games('close', obj.id);
      obj.id = [];
    end
  end
end
