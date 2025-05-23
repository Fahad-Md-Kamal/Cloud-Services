import codecs
import csv
import json
import logging

import azure.functions as func
from additional_functions import bp

app = func.FunctionApp()
app.register_blueprint(bp)


@app.function_name(name="FirstHTTPFunction")
@app.route(route="myroute", auth_level=func.AuthLevel.ANONYMOUS)
def test_function(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")

    return func.HttpResponse("Wow this is a test function", status_code=200)


@app.function_name(name="SecondHTTPFunction")
@app.route(route="newroute")
def test_function2(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")

    name = req.params.get("name")
    if name:
        return func.HttpResponse(f"Hello {name}")
    else:
        message = "Please pass a name on the query string or in the request body"

    return func.HttpResponse(message, status_code=200)


@app.function_name(name="MyFirstBlobFunction")
@app.blob_trigger(arg_name="myblob", path="newcontainer/{name}", connection="AzureWebJobsStorage")
def test_function3(myblob: func.InputStream):
    filename = myblob.name.split("/")[-1]
    logging.info(
        f"Python Blob trigger function after the {filename} file was uploaded to the newcontainer. So cool!!! \n"
        f"Printing the name of the blob path: {myblob.name}\n"
        f"Blob Size: {myblob.length} bytes"
    )


@app.function_name(name="ReadFileBlobFunction")
@app.blob_trigger(arg_name="readfile", path="newcontainer/{name}", connection="AzureWebJobsStorage")
def test_function_two(readfile: func.InputStream):
    reader = csv.DictReader(codecs.iterdecode(readfile, "utf-8"))
    rows = [row for row in reader]
    output_filename = f"output_{readfile.name.split('/')[-1].replace('.csv', '.json')}"
    with open(output_filename, "w") as f:
        json.dump(rows, f, indent=4)
