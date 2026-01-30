{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "spr";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "ejoffe";
    repo = "spr";
    rev = "v${version}";
    hash = "sha256-caEBsxajmjV7yr86WskkRBYBFzdV29wqu44fwMDowGw=";
  };

  vendorHash = "sha256-byl+MF0vlfa4V/3uPrv5Qlcvh5jIozEyUkKSSwlRWhs=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  # Tests require git repository setup
  doCheck = false;

  postInstall = ''
    # spr expects spr_reword_helper in PATH
    ln -s $out/bin/reword $out/bin/spr_reword_helper
  '';

  meta = with lib; {
    description = "Stacked Pull Requests on GitHub";
    homepage = "https://github.com/ejoffe/spr";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "spr";
  };
}
