# Model@RunTime Bash Template Generator

## Description:

Generates files from a given template by swapping its variables with values
found on a given martserver instance (or in a config file containing default
values). You must at least specify a valid -t parameter (template) and a
valid URL as the -r parameter (MartServer resource)/ a valid config file.

## Rationale

The easiest way to manage Cloud components is through configuration files, and in OCCIware the easiest way for adopters to let their custom extension's models have an impact at runtime has always been deemed to develop a (model to text) generator that transform them to such configuration files. However, until now there was no way to achieve that at Runtime, that is using MartServer-distributed models, since generators are only available in the OCCIware Studio.

MartBTG attempts to provide the simplest, lightest way to answer this need, that anybody can use - a smallest common denominator.

Because MartBTG has no other dependency than bash, it can be used with *any* OCCI implementation, not only MartServer, meaning that it is a good vector of evangelization of OCCIware, just like OCCInterface.

Beyond MartBTG, answers that would be deeper integrated with the OCCIware stack :
(1. pure bash : MartBTG)
2. OCCIware generators at runtime, client-side : at least package them, and wrap their existing code with a call to MartServer
3. OCCIware generators at runtime, server-side : package them in Mart and expose them as a dedicated REST API

## Usage

> **Note**: Before executing the script, please make sure it has execution rights, if not, set them with:

```bash
chmod u+x ./MartBTG.sh
```

### Generic Command:

```bash
./MartBTG.sh -t <PATH_TO_TEMPLATE> -r '<RESOURCE_URI>' [OPTION]...
```

### Template syntax

Variables are to be written javascript-like, between curly braces with a dollar sign before:

```bash
${<YOUR_VARIABLE_NAME>}
```

With **<YOUR_VARIABLE_NAME>** being for example **"attributes.occi.compute.state"**.

See example/template.txt for more examples.

### Config file syntax

Default values in the config file are to be written after the variable name and an equal sign, between double-quotes (no escaping implemented, don't use double-quotes in your default string values) like so:

```bash
attributes.occi.compute.state="active"
```

See example/config.txt for more examples.

### Typical usage:

```bash
./MartBTG.sh -t <PATH_TO_TEMPLATE> -r '<RESOURCE_URI>' -c <PATH_TO_CONFIG>
    -o <PATH_TO_OUTPUT> -u <USERNAME> -p
```

### Options:

+ -t, --template    Template file
+ -c, --config      Optional config file containing default values
+ -o, --output      Optional output file
+ -r, --resource    MartServer resource URL
+ -u, --username    Username for script. Must be used with -p.
+ -p, --password    User password. Must be used with -u before.
+ --force           Skip all user interaction.
+ -q, --quiet       Quiet (no output)
+ -l, --log         Print log to file
+ -s, --strict      Exit script with null variables.  i.e 'set -o nounset'
+ -v, --verbose     Output more information. (Items echoed to 'verbose')
+ -d, --debug       Runs script in BASH debug mode (set -x)
+ -h, --help        Display this help and exit
+ --version     Output version information and exit

### Example

You will need a running Martserver instance on your computer, with the OCCInterface. To do that, please check the official doc [MartServer github repository](https://github.com/occiware/MartServer/blob/master/doc/server.md).

Open the OCCInterface with with your web browser by going to http://localhost:8080/occinterface.

Click on the "EDIT" button, erase all of the text area content, and copy/paste the following one, and then click on "POST":

```json
{
    "title": "webserver",
    "summary": "server webpage for business site",
    "kind": "http://schemas.ogf.org/occi/infrastructure#compute",
    "attributes": {
        "occi.compute.speed": 3.0,
        "occi.compute.memory": 4.0,
        "occi.compute.cores": 8,
        "occi.compute.architecture": "x64",
        "occi.compute.state": "active"
    }
}
```

Then, to test the script so that it uses the information you just entered, simply execute the following command (and enter the default password, "1234"):

```bash
./MartBTG.sh -t example/template.txt -r 'http://localhost:8080/?category=compute&title=webserver' -c example/config.txt -u admin -p
```

You will be able to see the result in the command line, and compare it to the one of example/output.txt. If both are perfectly similar, then, this test is a success!

## Dependencies

> **Important Note: CURRENTLY ONLY SUPPORTS APT FOR AUTOMATIC DEPENDENCY INSTALLATION.**

Dependencies listing:

- jq for parsing json files
- curl to transfer data from a server

## Credits

> Boilerplate code from Nate Landau:
https://github.com/natelandau/shell-scripts
