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
- Downstream images can reconfigure log destinations by changing the TEAK_SERVICE environment variable for td-agent-bit. To do this, create a file in /lib/systemd/system/td-agent-bit.service.d/\*.conf with the contents ```
[Service]
Environment="TEAK_SERVICE={{service_name}}"
```
