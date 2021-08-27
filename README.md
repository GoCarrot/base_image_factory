# Base Image Factory

This provisions a Base Image from a previously created Root Image.

#### A note on terminology

We use `Root Image` to mean a completely unprovisioned bare image with nothing beyond a basic OS install. We use `Base Image` to mean a partially provisioned image with services required by all operational servers, e.g. monitoring, log aggregation, telemetry, etc.

## Local System Requirements
- packer >= 1.7.3
- ansible >= 4.3

## Image Specifications

When this image provides the option to include additional configuration files in a directory, file names must be prefixed with two digits and end in .conf. The prefixes 00 to 29 and 90 to 95 are reserved for use by this image.

The Base Image provides [FluentBit](https://fluentbit.io) as td-agent-bit, with the following defaults:
- systemd, cloudinit, and fluentbit logs are tailed under ancillary.{process}
- ancillary logs are outputted to cloudwatch_logs under /teak/server/{{ server_environment }}/ancillary/{{ process_name }}:{{ service_name }}.{{ hostname }}
- logs with the service.default tag will be outputted to /teak/server/{{ server_environment }}/service/{{ service_name }}:{{ service_name }}.{{ hostname }}
- Downstream images made add additional configuration for fluentbit in /etc/td-agent-bit/conf.d/\*.conf.
- Downstream images can reconfigure log destinations by changing the TEAK_SERVICE variable for td-agent-bit. To do this, create a file in /etc/td-agent-bit/conf.d/\*.conf with the contents ```@SET TEAK_SERVICE={{service_name}}```

FluentBit is not enabled by default in this image. This is so that downstream provisioning doesn't have to deal with the logging agent potentially attempting to push logs into an environment that doesn't accept logs, and to minimize cleanup between provisioning steps.

To enable FluentBit at boot, use the following user-data
```
#cloud-config
bootcmd:
  - [systemctl, enable, td-agent-bit]
  - [systemctl, start, --no-block, td-agent-bit]
```

This can/should be combined with a write_files config in order to set the service as well:

```
#cloud-config
bootcmd:
  - [systemctl, enable, td-agent-bit]
  - [systemctl, start, --no-block, td-agent-bit]
write_files:
  - path: /etc/td-agent-bit/conf.d/50_environment.conf
    content: "@SET TEAK_SERVICE=your_service"
```
