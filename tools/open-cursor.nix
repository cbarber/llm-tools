{
  lib,
  buildNpmPackage,
  bun,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "open-cursor";
  version = "2.5.8";

  src = fetchFromGitHub {
    owner = "Nomadcxx";
    repo = "opencode-cursor";
    rev = "v${version}";
    hash = "sha256-cDrLAEXomuolTikaWdXGWScYkLaPsH9JNkcl4PMzL6Q=";
  };

  npmDepsHash = "sha256-M8YmlLK8VVYq+RxF/YdmvJpjcqoKUDSPx7Bn0xGfhZI=";
  nativeBuildInputs = [ bun ];
  patches = [ ./patches/open-cursor-opencode-tool-loop.patch ];
  npmBuildScript = "build";
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bun test tests/unit/provider-tool-schema-compat.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/open-cursor"
    cp -r dist node_modules package.json "$out/lib/open-cursor/"
    runHook postInstall
  '';

  meta = {
    description = "Cursor subscription bridge for OpenCode";
    homepage = "https://github.com/Nomadcxx/opencode-cursor";
    license = lib.licenses.bsd3;
  };
}
