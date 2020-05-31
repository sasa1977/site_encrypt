# Changelog

## 0.3.0

### Breaking changes

- The internal folders structure has been changed. If you're running a site_encrypt system in production and using the certbot client, you need to create the folder `acme-v02.api.letsencrypt.org` (assuming you're using Let's Encrypt production) under `db_folder/certbot`, and then recursively copy the contents of `db_folder/certbot` into the new folder. If you're using the native client, you don't need to do anything.

folder called `certbot` inside the `:db_folder`, and recurisvely copy top-level folders under `:db_folder` into the newly created `certbot` folder.

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
