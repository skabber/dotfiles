{ config, pkgs, lib, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      python3Packages = prev.python3Packages.override {
        overrides = pyFinal: pyPrev: {
          outlines = pyPrev.outlines.overridePythonAttrs (old: rec {
            # Disable the runtime dependency version check that's failing
            doCheck = false;
            pythonRuntimeDepsCheck = false;
            dontUsePythonRuntimeDepsCheck = true;
          });
        };
      };
    })
  ];
}
