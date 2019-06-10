from envparse import env
from string import Template

import argparse
import json
import logging
import os
import pyodbc
import sys


logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

ch = logging.StreamHandler(sys.stdout)
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)


def get_params():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db_config",
                        help="--db_config <database config path>")
    parser.add_argument("--db_rows",
                        help="'--db_rows <database_rows_json_path>")
    parser.add_argument("--composite_keys",
                        help="'--composite_keys <results path>")
    params = parser.parse_args()

    if not os.path.isfile(params.db_rows):
        sys.exit("You need to specify an existing db rows path")
    if not os.path.isfile(params.db_config):
        sys.exit("You need to specify an existing db_config path")

    return params


def init_connection():
    connection = pyodbc.connect(get_connection_string())
    return connection, connection.cursor()


def get_connection_string():
    """Constructs the connection string for the DB with values from env file"""
    connection_string = Template("Driver={$SQLDriver};"
                                 "Server=$server,$port;"
                                 "Database=$db_name;"
                                 "Uid=$db_user;"
                                 "Pwd=$db_password;"
                                 "Encrypt=$encrypt;"
                                 "TrustServerCertificate=$certificate;"
                                 "Connection Timeout=$timeout;")

    return connection_string.substitute(
        SQLDriver=env.str('Driver'),
        server=env.str('Server'),
        port=env.str('Port'),
        db_name=env.str('Database'),
        db_user=env.str('User'),
        db_password=env.str('Password'),
        encrypt=env.str('Encrypt'),
        certificate=env.str('TrustServerCertificate'),
        timeout=env.str('ConnectionTimeout')
    )


def create_sql_query(values_dict, composite_keys):
    """Creates an update command from a template and calls the pyodbc method.

     Provided with a dictionary that is structured so the keys match the
     column names and the values are represented by the items that are to be
     inserted the function composes the sql command from a template and
     calls a pyodbc to execute the command.
    """
    sql_query_template = Template(
        """
        IF (NOT EXISTS(SELECT * FROM $tableName WHERE $compositeConditions))
        BEGIN
          INSERT INTO $tableName($columns) VALUES($insertValues)
        END
        ELSE
        BEGIN
          UPDATE TOP(1) $tableName SET $updateValues WHERE $compositeConditions
        END
    """
    )
    logger.debug('Line to be update %s', values_dict)
    insert_values = ''
    update_values = ''
    composite_conditions = ''
    table_name = '"' + env.str('TableName') + '"'
    valid_keys = []
    for k, v in values_dict.items():
        if (str(v)):
            insert_values = ', '.join([str(insert_values), "'" + str(v) + "'"])
            update_values = ', '.join([str(update_values),
                                      str(k) + " = " + "'" + str(v) + "'"])
            valid_keys.append(k)
        if k in composite_keys:
            composite_conditions = (' AND '.join([str(composite_conditions),
                                    str(k) + " = " + "'" + str(v) + "'"]))

    sql_query = sql_query_template.substitute(
        tableName=table_name,
        columns=', '.join(valid_keys),
        insertValues=insert_values[1:],
        updateValues=update_values[1:],
        compositeConditions=composite_conditions[5:]
        )

    logger.debug('SQL Query created:')
    logger.debug(sql_query)
    return sql_query


def execute_sql_query(sql_query, cursor):
    try:
        cursor.execute(sql_query)
    except pyodbc.DataError as data_error:
        print(dir(data_error))
        if data_error[0] == '22001':
            logger.error('Value to be updated exceeds column size limit')
        else:
            logger.error('Database update error', exc_info=True)

        logger.debug('Terminating execution')
        sys.exit(0)


def main():
    params = get_params()

    env.read_envfile(params.db_config)
    logger.debug('Initializing database connection')
    db_connection, db_cursor = init_connection()

    data = json.load(open(params.db_rows))

    composite_keys = params.composite_keys.split(",")

    for row in data:
        sql_query = create_sql_query(row, composite_keys)
        execute_sql_query(sql_query, db_cursor)

    logger.debug('Executing db commands')
    db_connection.commit()


main()
