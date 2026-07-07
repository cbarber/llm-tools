{
  lib,
  buildGoModule,
  fetchFromGitHub,
  bubblewrap,
  socat,
  makeWrapper,
  stdenv,
}:

buildGoModule {
  pname = "fence";
  version = "0.1.62";

  src = fetchFromGitHub {
    owner = "fencesandbox";
    repo = "fence";
    rev = "v0.1.62";
    hash = "sha256-uJfQFOKR3f8OjzA1z18IeKvhAgTmQQ7o4Y7K4CFbwko=";
  };

  vendorHash = "sha256-aMxay3dow6mDKyv396R0j1GOKDmhkX4ebGmhca1B4WE=";

  subPackages = [ "cmd/fence" ];

  nativeBuildInputs = [ makeWrapper ];

  # fence requires bubblewrap and socat at runtime on Linux
  postInstall = lib.optionalString stdenv.isLinux ''
    wrapProgram $out/bin/fence \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          socat
        ]
      }
  '';

  meta = {
    description = "Sandbox and network policy wrapper for AI coding agents";
    homepage = "https://github.com/fencesandbox/fence";
    license = lib.licenses.asl20;
    mainProgram = "fence";
    platforms = lib.platforms.unix;
  };
}
