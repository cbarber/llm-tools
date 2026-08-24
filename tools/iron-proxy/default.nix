{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "iron-proxy";
  version = "0.45.0";

  src = fetchFromGitHub {
    owner = "ironsh";
    repo = "iron-proxy";
    rev = "v0.45.0";
    hash = "sha256-f3fbf5C9Ima3qJkVakrydtra5gxNEyTSKk2oVv+Zjg4=";
  };

  proxyVendor = true;
  vendorHash = "sha256-PFnsyPwYd1llOgpcK7Ky6Zhz3xZ3IV6cXAUVjwwQC9M=";

  subPackages = [ "cmd/iron-proxy" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/ironsh/iron-proxy/internal/version.Version=0.45.0"
  ];

  meta = {
    description = "HTTPS intercepting proxy for AI coding agents — injects credentials at the HTTP layer";
    homepage = "https://github.com/ironsh/iron-proxy";
    license = lib.licenses.asl20;
    mainProgram = "iron-proxy";
    platforms = lib.platforms.unix;
  };
}
