# Azure Functions Trigger


## Commands

1. Create Function with command.

    ```sh
    func init MyFunctionProject --python -m v2
    ```

2. To add additional settings configs to `local.settings.json` use the following command:

    ```sh
    func settings add "<Variable-Name>" "<Value>"
    ```
    This will add additional fields to the `local.settings.json` file.

3. Start the function with the command:

    ```sh
    func start
    ```
    This command runs your Azure Functions project locally for testing and development.

## Files Information

- **`local.settings.json`**
  Stores local configuration settings for your Azure Functions project, such as environment variables and connection strings.

    ```json
    {
      "IsEncrypted": false,
      "Values": {
        "FUNCTIONS_WORKER_RUNTIME": "python",
        "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
        "AzureWebJobsStorage": "UseDevelopmentStorage=true"
      },
      "ConnectionStrings": {}
    }
    ```
    - `IsEncrypted`: Indicates if the file is encrypted.
    - `Values`: Key-value pairs for runtime and storage settings.
    - `ConnectionStrings`: Database or service connection strings.

- **`host.json`**
  Global configuration for all functions, including logging and extension bundles.

    ```json
    {
      "version": "2.0",
      "logging": {
        "applicationInsights": {
          "samplingSettings": {
            "isEnabled": true,
            "excludedTypes": "Request"
          }
        }
      },
      "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle",
        "version": "[4.*, 5.0.0)"
      }
    }
    ```
    - `version`: Host version.
    - `logging`: Application Insights and logging settings.
    - `extensionBundle`: Extension bundle configuration.

- **`requirements.txt`**
  Lists Python dependencies for your function app.

    ```
    azure-functions
    # Add other dependencies as needed
    ```

- **`docker-compose.yaml`**
  Docker Compose file for local development services (e.g., Azurite for storage emulation).

    ```yaml
    services:
      azurite:
        image: mcr.microsoft.com/azure-storage/azurite
        container_name: "azurite"
        hostname: azurite
        restart: always
        ports:
          - "10000:10000"
          - "10001:10001"
          - "10002:10002"
    ```
    - Defines a local Azurite storage emulator service.

- **`MyFunctionProject/function_app.py`**
  Main entry point for Azure Functions. Registers blueprints and defines triggers.

    ```python
    app = func.FunctionApp()
    app.register_blueprint(bp)

    @app.function_name(name="FirstHTTPFunction")
    @app.route(route="myroute", auth_level=func.AuthLevel.ANONYMOUS)
    def test_function(req: func.HttpRequest) -> func.HttpResponse: ...

    @app.function_name(name="SecondHTTPFunction")
    @app.route(route="newroute")
    def test_function(req: func.HttpRequest) -> func.HttpResponse: ...

    @app.function_name(name="MyFirstBlobFunction")
    @app.blob_trigger(
        arg_name="myblob",
        path="newcontainer/People.csv",
        connection="AzureWebJobsStorage")
    def test_function(myblob: func.InputStream): ...

    @app.function_name(name="ReadFileBlobFunction")
    @app.blob_trigger(
        arg_name="readfile",
        path="newcontainer/People2.csv",
        connection="AzureWebJobsStorage")
    def test_function_two(readfile: func.InputStream): ...
    ```
    - Registers HTTP and Blob trigger functions with their routes and parameters.

- **`MyFunctionProject/additional_functions.py`**
  Contains additional function blueprints.

    ```python
    bp = func.Blueprint()

    @bp.function_name(name="AdditionalFunction")
    @bp.route(route="brandnewroute")
    def additional_function(req: func.HttpRequest) -> func.HttpResponse: ...
    ```
    - Defines a blueprint and an HTTP-triggered function.

---

These files together define the structure, configuration, and triggers for Azure Functions project.

## Trigger Functions: Working Process, Connectivity, and Lifecycle

This project uses several Azure Functions triggers. Below is a summary of each trigger, its parameters, and how it connects within the app:

### 1. FirstHTTPFunction

```python
@app.function_name(name="FirstHTTPFunction")
@app.route(route="myroute", auth_level=func.AuthLevel.ANONYMOUS)
def test_function(req: func.HttpRequest) -> func.HttpResponse: ...
```
- **Trigger Type:** HTTP
- **Route:** `/api/myroute`
- **Auth Level:** Anonymous (no authentication required)
- **Parameter:**
  - `req`: The HTTP request object, used to access request data.

---

### 2. SecondHTTPFunction

```python
@app.function_name(name="SecondHTTPFunction")
@app.route(route="newroute")
def test_function(req: func.HttpRequest) -> func.HttpResponse: ...
```
- **Trigger Type:** HTTP
- **Route:** `/api/newroute`
- **Parameter:**
  - `req`: The HTTP request object, used to access query parameters (e.g., `name`).

---

### 3. MyFirstBlobFunction

```python
@app.function_name(name="MyFirstBlobFunction")
@app.blob_trigger(
    arg_name="myblob",
    path="newcontainer/People.csv",
    connection="AzureWebJobsStorage")
def test_function(myblob: func.InputStream): ...
```
- **Trigger Type:** Blob Storage
- **Blob Path:** `newcontainer/People.csv`
- **Connection:** Uses `AzureWebJobsStorage` connection string
- **Parameter:**
  - `myblob`: An InputStream representing the uploaded blob file.

---

### 4. ReadFileBlobFunction

```python
@app.function_name(name="ReadFileBlobFunction")
@app.blob_trigger(
    arg_name="readfile",
    path="newcontainer/People2.csv",
    connection="AzureWebJobsStorage")
def test_function_two(readfile: func.InputStream): ...
```
- **Trigger Type:** Blob Storage
- **Blob Path:** `newcontainer/People2.csv`
- **Connection:** Uses `AzureWebJobsStorage` connection string
- **Parameter:**
  - `readfile`: An InputStream for reading the blob file content.

---

### 5. AdditionalFunction (from blueprint)

```python
@bp.function_name(name="AdditionalFunction")
@bp.route(route="brandnewroute")
def additional_function(req: func.HttpRequest) -> func.HttpResponse: ...
```
- **Trigger Type:** HTTP (via blueprint)
- **Route:** `/api/brandnewroute`
- **Parameter:**
  - `req`: The HTTP request object.

---

**Lifecycle:**
- HTTP triggers respond to HTTP requests at their specified routes.
- Blob triggers activate when a blob is added or modified at the specified path in Azure Storage.
- All triggers are registered with the main `FunctionApp` instance and are discoverable by Azure Functions runtime.

---
