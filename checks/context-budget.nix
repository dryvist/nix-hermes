{
  pkgs,
  hermesBundle,
  donnaBundle,
}:

let
  tokenizerRevision = "482ca0f3832238542f8f5295dde86b5f22711d80";
  tokenizerJson = pkgs.fetchurl {
    url = "https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4/resolve/${tokenizerRevision}/tokenizer.json";
    hash = "sha256-CZf0EMV6H05TsJ5L6PShctkO3ZVkNo+whHAwk3IpufM=";
  };
  tokenizerPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tokenizers ]);
  counter = ./context-budget.py;
in
{
  context-budget = pkgs.runCommand "context-budget" { nativeBuildInputs = [ tokenizerPython ]; } ''
    set -euo pipefail
    status=0
    ${tokenizerPython}/bin/python ${counter} --tokenizer ${tokenizerJson} --bundle ${hermesBundle} --name hermes || status=1
    ${tokenizerPython}/bin/python ${counter} --tokenizer ${tokenizerJson} --bundle ${donnaBundle} --name donna || status=1
    [ "$status" -eq 0 ]
    touch "$out"
  '';

  context-budget-fixture =
    pkgs.runCommand "context-budget-fixture" { nativeBuildInputs = [ tokenizerPython ]; }
      ''
        set -euo pipefail
        mkdir -p fixture
        cp ${hermesBundle}/limits.json fixture/limits.json
        ${tokenizerPython}/bin/python ${counter} \
          --tokenizer ${tokenizerJson} \
          --limits fixture/limits.json \
          --make-oversized-fixture fixture/SOUL.md
        if ${tokenizerPython}/bin/python ${counter} --tokenizer ${tokenizerJson} --bundle fixture --name fixture > fixture/output.log 2>&1; then
          echo "context-budget accepted an oversized synthetic SOUL.md" >&2
          exit 1
        fi
        grep -q 'exceeds soul_base_max_tokens' fixture/output.log || {
          cat fixture/output.log >&2
          echo "context-budget fixture failed for a reason other than the base token budget" >&2
          exit 1
        }
        touch "$out"
      '';
}
