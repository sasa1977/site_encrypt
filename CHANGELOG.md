# 2020-05-25

More breaking changes have been introduced. If you've been using the older versions, here's how to upgrade your project:

1. In your endpoint, replace `@behaviour SiteEncrypt` with `use SiteEncrypt.Phoenix`
2. Also in the endpoint, change the `certification/0` callback to pass the options to `SiteEncrypt.configure/1` instead of just returning them.
3. Changes to options:
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

# 2020-05-10

A bunch of breaking changes have been introduced. If you've been using the older versions, here's how to upgrade your project.

1. Move `@behaviour SiteEncrypt` to your endpoint module.
2. Move `config/0` and `handle_new_cert/0` from the previous callback module to the endpoint, renaming `config/0` into `certification/0`
3. Modify `certification/0` to return a keyword list.
4. If you've used the `run_client?` option, replace it with `mode: if(Erlangelist.Config.certify(), do: :auto, else: :manual)`.
5. Replace `plug SiteEncrypt.AcmeChallenge, SomeModule` with `plug SiteEncrypt.AcmeChallenge, __MODULE__`.
6. Change the endpoint childspec to `{SiteEncrypt, YourEndpoint}`.

For inspiration, you can take a look at this [minimal endpoint implementation](https://github.com/sasa1977/site_encrypt/blob/master/demos/phoenix/lib/phoenix_demo/endpoint.ex).

