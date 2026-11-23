# Vector pieces shared by hosts and VMs: normalise journald and syslog
# records and write them to every host's VictoriaLogs.
{ lib }:
{
  # Fields VictoriaLogs groups streams by: short host name and unit/app name.
  # `names` maps sender addresses to names for devices that send no hostname.
  normalize =
    domain: names: inputs: {
      type = "remap";
      inherit inputs;
      source = ''
        if exists(.hostname) { .host = .hostname }
        .host = replace(to_string(.host) ?? "unknown", ".${domain}", "")
        ${lib.concatStrings (
          lib.mapAttrsToList (ip: name: ''
            if .host == "${ip}" { .host = "${name}" }
          '') names
        )}
        .unit = if exists(._SYSTEMD_UNIT) { ._SYSTEMD_UNIT } else if exists(.appname) { .appname } else { "unknown" }
        # Classic syslog carries no timezone; trust the receive time instead.
        if .source_type == "syslog" { .timestamp = now() }
      '';
    };

  # One sink per destination, each with its own disk buffer, so a host that is
  # down catches up later and never blocks the others.
  sinks =
    input: urls:
    lib.listToAttrs (
      lib.imap0 (i: url: {
        name = "victorialogs_${toString i}";
        value = {
          type = "elasticsearch";
          inputs = [ input ];
          endpoints = [ "${url}/insert/elasticsearch/" ];
          mode = "bulk";
          api_version = "v8";
          healthcheck.enabled = false;
          compression = "gzip";
          query = {
            _msg_field = "message";
            _time_field = "timestamp";
            _stream_fields = "host,unit";
          };
          buffer = {
            type = "disk";
            max_size = 268435488;
            when_full = "drop_newest";
          };
        };
      }) urls
    );
}
