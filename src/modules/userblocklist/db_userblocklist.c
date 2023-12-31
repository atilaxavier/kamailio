/*!
 * \file
 * \ingroup db
 * \brief Database support for modules.
 *
 * Database support functions for modules.
 *
 * @cond
 * WARNING:
 * This file was autogenerated from the XML source file
 * ../../modules/userblocklist/kamailio-userblocklist.xml.
 * It can be regenerated by running 'make modules' in the db/schema
 * directory of the source code. You need to have xsltproc and
 * docbook-xsl stylesheets installed.
 * ALL CHANGES DONE HERE WILL BE LOST IF THE FILE IS REGENERATED
 * @endcond
 */

#include "db_userblocklist.h"

/* database variables */
/* TODO assign read-write or read-only URI, introduce a parameter in XML */

//extern str userblocklist_db_url;
db1_con_t *userblocklist_dbh = NULL;
db_func_t userblocklist_dbf;

str userblocklist_table = str_init("userblocklist");

/* column names */
str userblocklist_id_col = str_init("id");
str userblocklist_username_col = str_init("username");
str userblocklist_domain_col = str_init("domain");
str userblocklist_prefix_col = str_init("prefix");
str userblocklist_allowlist_col = str_init("allowlist");

/* table version */
const unsigned int userblocklist_version = 1;

str globalblocklist_table = str_init("globalblocklist");

/* column names */
str globalblocklist_id_col = str_init("id");
str globalblocklist_prefix_col = str_init("prefix");
str globalblocklist_allowlist_col = str_init("allowlist");
str globalblocklist_description_col = str_init("description");

/* table version */
const unsigned int globalblocklist_version = 1;


/*
 * Closes the DB connection.
 */
void userblocklist_db_close(void)
{
	if(userblocklist_dbh) {
		userblocklist_dbf.close(userblocklist_dbh);
		userblocklist_dbh = NULL;
	}
}


/*!
 * Initialises the DB API and check the table version.
 * This should be called from the mod_init function.
 *
 * \return 0 means ok, -1 means an error occurred.
 */
int userblocklist_db_init(void)
{
	if(!userblocklist_db_url.s || !userblocklist_db_url.len) {
		LM_ERR("you have to set the db_url module parameter.\n");
		return -1;
	}
	if(db_bind_mod(&userblocklist_db_url, &userblocklist_dbf) < 0) {
		LM_ERR("can't bind database module.\n");
		return -1;
	}
	if((userblocklist_dbh = userblocklist_dbf.init(&userblocklist_db_url))
			== NULL) {
		LM_ERR("can't connect to database.\n");
		return -1;
	}
	if(db_check_table_version(&userblocklist_dbf, userblocklist_dbh,
			   &userblocklist_table, userblocklist_version)
			< 0) {
		DB_TABLE_VERSION_ERROR(userblocklist_table);
		userblocklist_db_close();
		return -1;
	}
	if(db_check_table_version(&userblocklist_dbf, userblocklist_dbh,
			   &globalblocklist_table, globalblocklist_version)
			< 0) {
		DB_TABLE_VERSION_ERROR(globalblocklist_table);
		userblocklist_db_close();
		return -1;
	}
	return 0;
}


/*!
 * Initialize the DB connection without checking the table version and DB URL.
 * This should be called from child_init. An already existing database
 * connection will be closed, and a new one created.
 *
 * \return 0 means ok, -1 means an error occurred.
 */
int userblocklist_db_open(void)
{
	if(userblocklist_dbh) {
		userblocklist_dbf.close(userblocklist_dbh);
	}
	if((userblocklist_dbh = userblocklist_dbf.init(&userblocklist_db_url))
			== NULL) {
		LM_ERR("can't connect to database.\n");
		return -1;
	}
	return 0;
}
