{ buildNpmPackage, bun }:

buildNpmPackage {
  pname = "opencode-temper-plugin";
  version = "0.1.0";
  src = ./.;
  npmDepsHash = "sha256-mIwxrHlZjXGyMx9gE7f8jMeDokBjZWylvIbzmK6tOhM=";
  npmDepsFetcherVersion = 2;
  npmFlags = [
    "--omit=dev"
    "--legacy-peer-deps"
  ];
  nativeBuildInputs = [ bun ];
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    bun run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/temper
    cp dist/temper.js $out/lib/temper/temper.js
    runHook postInstall
  '';
}
