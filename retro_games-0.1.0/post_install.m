function post_install (desc)
  %POST_INSTALL  Executado automaticamente após pkg install.
  % No Linux: remove cores/windows (fica só .so)
  % No Windows: remove cores/linux (fica só .dll)

  pkg_dir   = desc.dir;
  cores_dir = fullfile(pkg_dir, 'cores');

  if ispc()
    d = fullfile(cores_dir, 'linux');
    if exist(d, 'dir'), rmdir(d, 's'); end
  else
    d = fullfile(cores_dir, 'windows');
    if exist(d, 'dir'), rmdir(d, 's'); end
  end
end
