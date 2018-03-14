from envparse import env
from string import Template

import json
import logging
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
        db_password=env.str('Pa'),
        encrypt=env.str('Encrypt'),
        certificate=env.str('TrustServerCertificate'),
        timeout=env.str('ConnectionTimeout')
    )


def insert_values(cursor, values_dict):
    """Creates an insert command from a template and calls the pyodbc method.

     Provided with a dictionary that is structured so the keys match the
     column names and the values are represented by the items that are to be
     inserted the function composes the sql command from a template and
     calls a pyodbc to execute the command.
    """
    insert_command_template = Template(
        'insert into $tableName($columns) values($values)'
    )
    logger.debug('Line to be inserted %s', values_dict)
    values = ''
    table_name = '"' + env.str('TableName') + '"'
    for item in values_dict.values():
        values = ', '.join([str(values), "'" + str(item) + "'"])

    insert_command = insert_command_template.substitute(
        tableName=table_name,
        columns=', '.join(values_dict.keys()),
        values=values[1:]
        )

    logger.debug('Insert command that will be exectued:')
    logger.debug(insert_command)

    try:
        cursor.execute(insert_command)
    except pyodbc.DataError as data_error:
        print(dir(data_error))
        if data_error[0] == '22001':
            logger.error('Value to be inserted exceeds column size limit')
        else:
            logger.error('Database insertion error', exc_info=True)

        logger.debug('Terminating execution')
        sys.exit(0)


def update_values(cursor, values_dict, composite_keys):
    """Creates an update command from a template and calls the pyodbc method.

     Provided with a dictionary that is structured so the keys match the
     column names and the values are represented by the items that are to be
     inserted the function composes the sql command from a template and
     calls a pyodbc to execute the command.
    """
    update_command_template = Template(
        """
        IF (NOT EXISTS(SELECT * FROM $tableName WHERE $compositeConditions))
        BEGIN
            INSERT INTO $tableName($columns) VALUES($insertValues)
        END
        ELSE
        BEGIN
            UPDATE $tableName SET $updateValues WHERE $compositeConditions
        END
    """
    )
    logger.debug('Line to be update %s', values_dict)
    insert_values = ''
    update_values = ''
    composite_conditions = ''
    table_name = '"' + env.str('TableName') + '"'
    for k, v in values_dict.items():
        insert_values = ', '.join([str(insert_values), "'" + str(v) + "'"])
        update_values = ', '.join([str(update_values),
                                  str(k) + " = " + "'" + str(v) + "'"])
        if k in composite_keys:
            composite_conditions = (' AND '.join([str(composite_conditions),
                                    str(k) + " = " + "'" + str(v) + "'"]))

    update_command = update_command_template.substitute(
        tableName=table_name,
        columns=', '.join(values_dict.keys()),
        insertValues=insert_values[1:],
        updateValues=update_values[1:],
        compositeConditions=composite_conditions[5:]
        )

    logger.debug('Update command that will be exectued:')
    logger.debug(update_command)

    try:
        cursor.execute(update_command)
    except pyodbc.DataError as data_error:
        print(dir(data_error))
        if data_error[0] == '22001':
            logger.error('Value to be updated exceeds column size limit')
        else:
            logger.error('Database update error', exc_info=True)

        logger.debug('Terminating execution')
        sys.exit(0)


def main():
    env.read_envfile('db.config')
    logger.debug('Initializing database connection')
    db_connection, db_cursor = init_connection()

    data = json.load(open('tests.json'))

    for row in data:
        print(row)
        update_values(db_cursor, row, ('PipelineName', 'PipelineBuildNumber'))

    logger.debug('Executing db commands')
    db_connection.commit()


main()