# Base Image Factory

This provisions a Base Image from a previously created Root Image.

#### A note on terminology

We use `Root Image` to mean a completely unprovisioned bare image with nothing beyond a basic OS install. We use `Base Image` to mean a partially provisioned image with services required by all operational servers, e.g. monitoring, log aggregation, telemetry, etc.

## Local System Requirements
- packer >= 1.7.3
- ansible >= 4.3

## Image Specifications

When this image provides the option to include additional configuration files in a directory, file names must be prefixed with two digits and end in .conf. The prefixes 00 to 29 and 90 to 95 are reserved for use by this image.

### TEAK_SERVICE

The Base Image configures systemd to provide a TEAK_SERVICE environment variable to all systemd services with names starting with `teak-`. By default TEAK_SERVICE will be set to the name of the base image AMI. In non-AMI environments, TEAK_SERVICE will be set to "unknown". To modify this create a configuration file in /etc/systemd/system/teak-.service.d/ with the contents

```
[Service]
Environment="TEAK_SERVICE={{service_name}}"
```

### teak-init.target

The Base Image provides teak-init.target, which will not be active until all services provided by the Base Image are available. Downstream services should set `After=teak-init.target` in their unit configurations.

### FluentBit

The Base Image provides [FluentBit](https://fluentbit.io) as teak-log-collector, with the following defaults:
- systemd, cloudinit, fluentbit, and configurator logs are tailed under ancillary.{process}
- ancillary logs are outputted to cloudwatch_logs under /fb/server/{{ server_environment }}/ancillary/{{ process_name }}:{{ service_name }}.{{ hostname }}
- logs with the service.default tag will be outputted to /fb/server/{{ server_environment }}/service/{{ service_name }}:{{ service_name }}.{{ hostname }}
- Downstream images may add additional configuration for fluentbit in /etc/teak-log-collector/conf.d/\*.conf.

FluentBit is enabled by default in this image.

#### Special Configuration Notes
Because FluentBit does not allow glob matches for parser or plugins config, and does not allow configuring parsers or plugins in normal config files, this image provides the files /etc/td-agent-bit/10_service_plugins.conf and /etc/td-agent-bit/10_service_parsers.conf. Downstream provisioners may _append_ content to these files in order to provide plugins and parsers for their usecases.

#### Disabling FluentBit
To disable FluentBit at boot, use the following user-data
```
#cloud-config
bootcmd:
  - [systemctl, stop, --no-block, teak-log-collector]
```

Be sure to wipe `/var/lib/cloud` after provisioning so that this user-data does not persist to live servers.

It is recommended that FluentBit remain enabled so that the server logs from the build process running be logged to CloudWatch.

### Configurator

The Base Image provides the [configurator](https://github.com/GoCarrot/configurator) as teak-configurator.

teak-configurator is enabled by default in this image.

As the Base Image provides no "metaconfiguration" for the configurator it will not actually do anything.

### newrelic-infra

The Base Image provides [NewRelic Infrastructure Monitoring](https://docs.newrelic.com/docs/infrastructure/install-infrastructure-agent/).

newrelic-infra is disabled by default.

To enable newrelic-infra, add a newrelic-infra.yml configuration file in /etc/newrelic-infra/newrelic-infra.yml with your NewRelic license key.
