# 2020-05-10

A bunch of breaking changes have been introduced. If you've been using the older versions, here's how to upgrade your project.

1. Move `@behaviour SiteEncrypt` to your endpoint module.
2. Move `config/0` and `handle_new_cert/0` from the previous callback module to the endpoint, renaming `config/0` into `certification/0`
3. Modify `certification/0` to return a keyword list.
4. If you've used the `run_client?` option, replace it with `mode: if(Erlangelist.Config.certify(), do: :auto, else: :manual)`.
5. Replace `plug SiteEncrypt.AcmeChallenge, SomeModule` with `plug SiteEncrypt.AcmeChallenge, __MODULE__`.
6. Change the endpoint childspec to `{SiteEncrypt, YourEndpoint}`.

For inspiration, you can take a look at this [minimal endpoint implementation](https://github.com/sasa1977/site_encrypt/blob/master/demos/phoenix/lib/phoenix_demo/endpoint.ex).

