function p = retro_games_paths()
  %RETRO_GAMES_PATHS  Retorna diretórios usados pelo pacote retro_games.
  pkgs = pkg('list', 'retro_games');
  if isempty(pkgs)
    error('retro_games_paths: pacote retro_games nao encontrado (use pkg load retro_games).');
  end
  pkg_dir = pkgs{1}.dir;
  p.pkg_dir  = pkg_dir;
  p.core_dir = fullfile(pkg_dir, 'cores');
  p.rom_dir  = fullfile(pkg_dir, 'roms');
end
