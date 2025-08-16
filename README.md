# bread-kit

## setup

create `.env` file:

```shell
cp .env.example .env
```

replace `ETH_RPC_URL` to your own custom gnosis chain quicknode rpc endpoint.

## test

```shell
forge compile
```

```shell
forge test -vv
```