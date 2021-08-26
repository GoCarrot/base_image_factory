# Base Image Factory

This provisions a Base Image from a previously created Root Image.

#### A note on terminology

We use `Root Image` to mean a completely unprovisioned bare image with nothing beyond a basic OS install. We use `Base Image` to mean a partially provisioned image with services required by all operational servers, e.g. monitoring, log aggregation, telemetry, etc.

## Local System Requirements
- packer >= 1.7.3
- ansible >= 4.3

## Image Specifications

The Base Image provides [FluentBit](https://fluentbit.io) as td-agent-bit, with the following enhancements:
- Downstream images made add additional configuration for fluentbit in /etc/td-agent-bit/conf.d/\*.conf. Files must be prefixed with two digits. 00 to 29 and 90 to 95 are reserved for use by this image.
