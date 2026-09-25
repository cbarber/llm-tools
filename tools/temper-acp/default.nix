{ rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "temper-acp";
  version = "0.1.0";
  src = ./.;
  cargoHash = "sha256-cAUOQBHsdi3ekRU0pRuvfsnKdUnrPgzKxeCMs/QtLII=";
}
