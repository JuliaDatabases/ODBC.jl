
# ODBC

*A Julia library for interacting with the ODBC API*

| **Documentation**                                                               | **Build Status**                |
|:-------------------------------------------------------------------------------:|:-------------------------------:|
| [![][docs-stable-img]][docs-stable-url] [![][docs-latest-img]][docs-latest-url] | [![][codecov-img]][codecov-url] |


## Installation

The package is registered in the `General` registry and so can be installed with `Pkg.add`.

```julia
julia> using Pkg; Pkg.add("ODBC")
```

## Documentation

- [**STABLE**][docs-stable-url] &mdash; **most recently tagged version of the documentation.**
- [**LATEST**][docs-latest-url] &mdash; **in-development version of the documentation.**

## Project Status

The package is tested against Julia `1.3+` on Linux, OSX, and Windows.

## Contributing and Questions

Contributions are very welcome, as are feature requests and suggestions. Please open an
[issue][issues-url] if you encounter any problems or would just like to ask a question.



[docs-latest-img]: https://img.shields.io/badge/docs-latest-blue.svg
[docs-latest-url]: https://odbc.juliadatabases.org/latest

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://odbc.juliadatabases.org/stable

[codecov-img]: https://codecov.io/gh/JuliaDatabases/ODBC.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/JuliaDatabases/ODBC.jl

[issues-url]: https://github.com/JuliaDatabases/ODBC.jl/issues

## Testing

To run tests locally on Linux, you need to have
  - the MariaDB ODBC connectors downloaded and in a specific directory (as per `.travis.yml`):
    ```sh
    curl -O https://downloads.mariadb.com/Connectors/odbc/connector-odbc-3.1.7/mariadb-connector-odbc-3.1.7-ga-debian-x86_64.tar.gz
    mkdir mariadb64; tar xfz mariadb-connector-odbc-3.1.7-ga-debian-x86_64.tar.gz -C mariadb64
    curl -O https://downloads.mariadb.com/Connectors/odbc/connector-odbc-3.1.7/mariadb-connector-odbc-3.1.7-ga-debian-i686.tar.gz
    mkdir mariadb32; tar xfz mariadb-connector-odbc-3.1.7-ga-debian-i686.tar.gz -C mariadb32MySQL
    ```
  - MariaDB listening on 127.0.0.1:3306 with root user `root` having an empty password. An easy way to do this is with docker:
    ```sh
    docker run -e MYSQL_ALLOW_EMPTY_PASSWORD=1  -it -p 3306:3306 mysql
    ```

  - the `TRAVIS_BUILD_DIR` env var set before running tests.
    ```
    env TRAVIS_BUILD_DIR=$(pwd) julia --project=@.
    julia> ]
    (ODBC) pkg> test
    ```

The MariaDB ODBC connector for Windows can be downloaded from 
https://dlm.mariadb.com/3286254/Connectors/odbc/connector-odbc-3.1.19/mariadb-connector-odbc-3.1.19-win64.msi

For my (@ahjulstad) the testing done on Windows I used docker compose. 