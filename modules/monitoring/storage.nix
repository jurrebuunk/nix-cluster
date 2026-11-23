# Full copies on every host: vmagent and Vector write to all three, so any one
# host can answer every query. Data lives on the local NVMe.
{ inventory, ... }:
let
  cfg = inventory.monitoring;
in
{
  services.victoriametrics = {
    enable = true;
    listenAddress = ":8428";
    retentionPeriod = cfg.retention.metrics;
    extraOptions = [
      # Shared targets (router, switch) are scraped by every host.
      "-dedup.minScrapeInterval=30s"
      "-memory.allowedBytes=512MB"
    ];
  };

  services.victorialogs = {
    enable = true;
    listenAddress = ":9428";
    extraOptions = [
      "-retentionPeriod=${cfg.retention.logs}"
      "-retention.maxDiskSpaceUsageBytes=20GiB"
      "-memory.allowedBytes=512MB"
    ];
  };
}
