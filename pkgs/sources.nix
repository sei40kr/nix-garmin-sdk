# sources.json, with the SDK release lines (major versions) sorted newest first.
{ lib }:

let
  json = lib.importJSON ../sources.json;
  majors = lib.sort (a: b: lib.versionOlder b a) (lib.attrNames json.sdks);
in
{
  inherit (json) sdks sdkManager;
  inherit majors;
  latestMajor = lib.head majors;
}
