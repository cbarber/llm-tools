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
    owner = "cbarber";
    repo = "opencode-cursor";
    rev = "55bc3956f8b1e54e734cc777edca01f0407e9f1c";
    hash = "sha256-uLRndAkL5wlLLtIukuHjdo85pghFVdbpTGur5Yplbyo=";
  };

  npmDepsHash = "sha256-ufqxSzvmtnxhL+zRkVVvnCVjLZ5m+aNRmeS8wvFVlAg=";
  nativeBuildInputs = [ bun ];
  npmBuildScript = "build";
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bun test tests/unit/plugin-proxy-reuse.test.ts tests/unit/provider-backend.test.ts tests/unit/provider-tool-schema-compat.test.ts tests/unit/proxy/plugin-resume.test.ts tests/unit/sdk-runner.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/open-cursor"
    cp -r dist node_modules package.json scripts "$out/lib/open-cursor/"
    runHook postInstall
  '';

  meta = {
    description = "Cursor subscription bridge for OpenCode";
    homepage = "https://github.com/cbarber/opencode-cursor";
    license = lib.licenses.bsd3;
  };
}
