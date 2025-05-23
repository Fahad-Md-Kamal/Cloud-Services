import logging

import azure.functions as func

bp = func.Blueprint()


@bp.function_name(name="AdditionalFunction")
@bp.route(route="brandnewroute")
def additional_function(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")

    return func.HttpResponse("Wow this worked", status_code=200)
