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

### Fluentd

The Base Image provides [Fluentd](https://www.fluentd.org) as teak-log-collector, with the following defaults:

- systemd, cloudinit, fluentd, and configurator logs are tailed under ancillary.{process}
- ancillary logs are outputted to cloudwatch_logs under /teak/server/{{ server_environment }}/ancillary/{{ process_name }}:{{ service_name }}.{{ hostname }}
- logs with the service.default tag will be outputted to /teak/server/{{ server_environment }}/service/{{ service_name }}:{{ service_name }}.{{ hostname }}
- Downstream images may add additional configuration for fluentd in /etc/fluent/conf.d/\*.conf.

Fluentd is enabled by default in this image.

#### Disabling Fluentd

To disable Fluentd at boot, use the following user-data

```yml
#cloud-config
bootcmd:
  - [systemctl, stop, --no-block, teak-log-collector]
```

Be sure to wipe `/var/lib/cloud` after provisioning so that this user-data does not persist to live servers.

It is recommended that Fluentd remain enabled so that the server logs from the build process running be logged to CloudWatch.

### Config O-Mat

The Base Image provides the [config_o_mat](https://github.com/GoCarrot/config_o_mat) as teak-configurator.

teak-configurator is enabled by default in this image.

As the Base Image provides no "metaconfiguration" for the configurator it will not actually do anything.

### newrelic-infra

The Base Image provides [NewRelic Infrastructure Monitoring](https://docs.newrelic.com/docs/infrastructure/install-infrastructure-agent/).

newrelic-infra is disabled by default.

To enable newrelic-infra, add a newrelic-infra.yml configuration file in /etc/newrelic-infra/newrelic-infra.yml with your NewRelic license key.
