{
  lib,
  python314Packages,
  fetchurl,
}:

let
  format-currency = python314Packages.buildPythonPackage {
    pname = "format-currency";
    version = "0.0.10";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/94/cb/788941330c524422c87583121b0d589636a982fad0685f9f3b7c7588c2f4/format_currency-0.0.10-py3-none-any.whl";
      hash = "sha256-7t7PCyxNIbJDXv8+7ZVlgWDQYCxET5Id0izkv6t3Ncc=";
    };
  };
  textual-diff-view = python314Packages.buildPythonPackage {
    pname = "textual-diff-view";
    version = "0.1.5";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/2d/b3/891eb302e7bb037b308cd2960ba0f762fa1e95f574c1ed810b23c86326a1/textual_diff_view-0.1.5-py3-none-any.whl";
      hash = "sha256-Lpx8fzfRlWiNDfVvcFbpWA5PQMNYODSxI2YZm3d5jzU=";
    };
    dependencies = [ python314Packages.textual ];
  };
in
python314Packages.buildPythonApplication {
  pname = "batrachian-toad";
  version = "0.6.20";
  pyproject = true;
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/18/74/7e2940e892fc322b94d0b9de0e47ed24fb0f4563f0c7d7458256a3a72c66/batrachian_toad-0.6.20.tar.gz";
    hash = "sha256-pmHuY834ab6N5fRIMUgpK35VCVx7uyjwtIYo+SLYIdU=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail 'hatchling==1.28.0' hatchling
  '';
  build-system = [ python314Packages.hatchling ];
  dependencies = with python314Packages; [
    aiosqlite
    bashlex
    click
    format-currency
    httpx
    notify-py
    packaging
    pathspec
    platformdirs
    psutil
    pyperclip
    rich
    setproctitle
    textual
    textual-diff-view
    textual-serve
    textual-speedups
    typeguard
    typing-extensions
    watchdog
    xdg-base-dirs
  ];
  pythonRelaxDeps = true;

  meta = {
    description = "Unified terminal interface for AI agents";
    homepage = "https://github.com/batrachianai/toad";
    license = lib.licenses.agpl3Only;
    mainProgram = "toad";
  };
}
