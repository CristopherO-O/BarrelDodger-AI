function varargout = retro_games(varargin)
  %RETRO_GAMES  Wrapper principal para o MEX libretro_bridge.
  if exist('libretro_bridge', 'file') ~= 3
    error(['retro_games: MEX libretro_bridge nao encontrado. ' ...
           'Instale/compile o pacote com pkg install e verifique o build.']);
  end
  [varargout{1:nargout}] = libretro_bridge(varargin{:});
end
