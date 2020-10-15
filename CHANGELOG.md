# Changelog

## 0.4.0

This version upgrades to the Parent 0.11 and changes the internals. Strictly speaking this version doesn't change anything, so it could have been a patch update. However, moving to Parent 0.11 might introduce breaking changes in the client code, so the major version is bumped.

## 0.3.1

- Fixes invalid dependency requirement.

## 0.3.0

### Additions and non-breaking changes

- Exposed lower-level ACME client API functions through `SiteEncrypt.Acme.Client` and `SiteEncrypt.Acme.Client.API`.
- Native client keeps the history of old keys.
- Key size is configurable, with the default of 4096.
- Added support for manual production testing through `SiteEncrypt.dry_certify/2`. See "Testing in production" section in readme for details.
- Renewal happens at a random time of day to avoid possible spikes on CA.

### Breaking changes

- The internal folders structure has been changed. If you're running a site_encrypt system in production and using the certbot client, you need to create the folder `acme-v02.api.letsencrypt.org` (assuming you're using Let's Encrypt production) under `db_folder/certbot`, and then recursively copy the contents of `db_folder/certbot` into the new folder. If you're using the native client, you don't need to do anything.

## 0.2.0

### Breaking changes

- The interface for writing tests has been changed. A certification test should now be written as

    ```elixir
    defmodule MyEndpoint.CertificationTest do
      use ExUnit.Case, async: false
      import SiteEncrypt.Phoenix.Test

      test "certification" do
        clean_restart(MyEndpoint)
        cert = get_cert(MyEndpoint)
        assert cert.domains == ~w/mysite.com www.mysite.com/
      end
    end
    ```

## 0.1.0

- added a basic native ACME client
- simplified interface
- improved tests
- expanded docs

This version introduces many breaking changes. If you've been using a pre 0.1 version, here's how to upgrade your project:

1. In your endpoint, replace `@behaviour SiteEncrypt` with `use SiteEncrypt.Phoenix`
2. Also in the endpoint, change the `certification/0` callback to pass the options to `SiteEncrypt.configure/1` instead of just returning them.
3. Changes in options:
    - `:mode` is no longer supported. Manual mode will be automatically set in tests.
    - use `:domains` instead of `:domain` and `:extra_domain`
    - `:ca_url` has been renamed to `directory_url`
    - `:email` has been renamed to `emails` and must be a list
    - `:base_folder` has been renamed to `:db_folder`
    - `:cert_folder` is no longer supported. It will chosen automatically inside the `:db_folder`
4. The internal folders structure has been changed. If you're running a site_encrypt system in production, you need to create the folder called `certbot` inside the `:db_folder`, and recurisvely copy top-level folders under `:db_folder` into the newly created `certbot` folder.
5. If you have been using `SiteEncrypt.Phoenix.Test.verify_certification` for certification testing, drop that test, and add the following module somewhere in your test suite:
    ```elixir
    defmodule CertificationTest do
      use SiteEncrypt.Phoenix.Test, endpoint: MyEndpoint
    end
    ```
