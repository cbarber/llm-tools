{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "spr";
  version = "0.15.1";

  src = fetchFromGitHub {
    owner = "ejoffe";
    repo = "spr";
    rev = "v${version}";
    hash = "sha256-477ERmc7hQzbja5qWLI/2zz8gheIEpmMLQSp2EOjjMY=";
  };

  vendorHash = "sha256-vTmzhU/sJ0C8mYuLE8qQQELI4ZwQVv0dsM/ea1mlhFk=";

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
