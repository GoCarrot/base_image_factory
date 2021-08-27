# Base Image Factory

This provisions a Base Image from a previously created Root Image.

#### A note on terminology

We use `Root Image` to mean a completely unprovisioned bare image with nothing beyond a basic OS install. We use `Base Image` to mean a partially provisioned image with services required by all operational servers, e.g. monitoring, log aggregation, telemetry, etc.

## Local System Requirements
- packer >= 1.7.3
- ansible >= 4.3

## Image Specifications

When this image provides the option to include additional configuration files in a directory, file names must be prefixed with two digits and end in .conf. The prefixes 00 to 29 and 90 to 95 are reserved for use by this image.

### FluentBit

The Base Image provides [FluentBit](https://fluentbit.io) as td-agent-bit, with the following defaults:
- systemd, cloudinit, and fluentbit logs are tailed under ancillary.{process}
- ancillary logs are outputted to cloudwatch_logs under /teak/server/{{ server_environment }}/ancillary/{{ process_name }}:{{ service_name }}.{{ hostname }}
- logs with the service.default tag will be outputted to /teak/server/{{ server_environment }}/service/{{ service_name }}:{{ service_name }}.{{ hostname }}
- Downstream images made add additional configuration for fluentbit in /etc/td-agent-bit/conf.d/\*.conf.
- Downstream images can reconfigure log destinations by changing the TEAK_SERVICE variable for td-agent-bit. To do this, create a file in /etc/td-agent-bit/conf.d/\*.conf with the contents ```@SET TEAK_SERVICE={{service_name}}```

FluentBit is enabled by default in this image.

#### Special Configuration Notes
Because FluentBit does not allow glob matches for parser or plugins config, and does not allow configuring parsers or plugins in normal config files, this image provides the files /etc/td-agent-bit/10_service_plugins.conf and /etc/td-agent-bit/10_service_parsers.conf. Downstream provisioners may _append_ content to these files in order to provide plugins and parsers for their usecases.

#### Disabling FluentBit
Downstream provisioners almost certainly do not want FluentBit running while they are doing provisioning.

To disable FluentBit at boot, use the following user-data
```
#cloud-config
bootcmd:
  - [systemctl, stop, --no-block, td-agent-bit]
```

Be sure to wipe `/var/lib/cloud` after provisioning so that this user-data does not persist to live servers.
