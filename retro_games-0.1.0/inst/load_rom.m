function game = load_rom(rom_path)
  %LOAD_ROM  Carrega uma ROM e retorna um objeto RetroGame.
  %
  % Suporta (pela extensao):
  %   .nes         -> NES (FCEUmm)
  %   .gba         -> GBA (mGBA)
  %   .sfc,.smc    -> SNES (Snes9x)
  %   .bin,.md     -> Mega Drive
  %   .sms,.gg     -> Master System / Game Gear
  %   .a26         -> Atari 2600 (Stella)
  %
  % Botoes: [start, select, up, down, left, right, A, B, C, X, Y, Z, L, R]

  if nargin < 1
    error('load_rom: caminho da ROM nao informado.');
  end

  rom_path = char(rom_path);
  p = retro_games_paths();

  % tenta caminho direto, depois rom_dir
  if exist(rom_path, 'file') ~= 2
    cand_rom = fullfile(p.rom_dir, rom_path);
    if exist(cand_rom, 'file') == 2
      rom_path = cand_rom;
    else
      error('load_rom: arquivo ROM nao encontrado (nem em "%s" nem em "%s").', ...
            rom_path, cand_rom);
    end
  end

  [~,~,ext] = fileparts(lower(rom_path));

  system_name = '';
  core_linux = '';
  core_win   = '';

  switch ext
    case '.nes'
      core_linux = fullfile(p.core_dir, 'linux',   'fceumm_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'fceumm_libretro.dll');
      system_name = 'nes';

    case '.gba'
      core_linux = fullfile(p.core_dir, 'linux',   'mgba_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'mgba_libretro.dll');
      system_name = 'gba';

    case {'.sfc', '.smc'}
      core_linux = fullfile(p.core_dir, 'linux',   'snes9x_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'snes9x_libretro.dll');
      system_name = 'snes';

    case {'.bin', '.md'}
      core_linux = fullfile(p.core_dir, 'linux',   'genesis_plus_gx_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'genesis_plus_gx_libretro.dll');
      system_name = 'megadrive';

    case {'.sms', '.gg'}
      core_linux = fullfile(p.core_dir, 'linux',   'genesis_plus_gx_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'genesis_plus_gx_libretro.dll');
      system_name = 'sms_gg';

    case '.a26'
      core_linux = fullfile(p.core_dir, 'linux',   'stella_libretro.so');
      core_win   = fullfile(p.core_dir, 'windows', 'stella_libretro.dll');
      system_name = 'atari2600';

    otherwise
      error('load_rom: extensao de ROM nao suportada: %s', ext);
  end

  if ispc()
    core_path = core_win;
  else
    core_path = core_linux;
  end

  if exist(core_path, 'file') ~= 2
    error(['load_rom: core Libretro nao encontrado para "%s".\n' ...
           'Esperado em:\n  %s\nVerifique se os cores foram baixados e se o post_install removeu o SO oposto.'], ...
           ext, core_path);
  end

  id = retro_games('load_rom', core_path, rom_path, system_name);
  game = RetroGame(id, system_name, core_path, rom_path);
end
