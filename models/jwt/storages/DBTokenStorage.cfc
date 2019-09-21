/**
 * Copyright since 2016 by Ortus Solutions, Corp
 * www.ortussolutions.com
 * ---
 * A Database based token storage.
 *
 * Properties
 * - table : the table to use
 * - schema : the schema to use (if db support it)
 * - dsn : the dsn to use, no dsn, we use the global one
 * - autoCreate : if true, then we will create the table. Defaults to true
 *
 * The columns needed in the table are
 *
 * - id : db identifier
 * - cacheKey : varchar 255
 * - token : text
 * - expiration : varchar 255 (unix timestamp)
 *
 */
component accessors="true" singleton{

	// DI
	property name="wirebox" 	inject="wirebox";
	property name="cachebox" 	inject="cachebox";
	property name="settings" 	inject="coldbox:moduleSettings:cbSecurity";

	/**
	 * Storage properties
	 */
	property name="properties";

	/**
	 * The linked cache provider
	 */
	property name="cache";

	/**
	 * The configured key prefix for the storage
	 */
	property name="keyPrefix";

	variables.COLUMNS = "id,cacheKey,token,expiration,created";

	/**
	 * Constructor
	 */
	function init(){
		// UUID generator
		variables.uuid 		= createobject( "java", "java.util.UUID" );
		// Settings
		variables.settings 	= {};
		// Lucee Indicator
		variables.isLucee 	= server.keyExists( "lucee" );
		return this;
	}

	 /**
     * Configure the storage by passing in the properties
	 *
	 * @properties The storage properties
     *
     * @return JWTStorage
     */
    any function configure( required properties ){
		variables.properties = arguments.properties;

		// Setup Properties
		if( isNull( variables.properties.table ) ){
			throw( message="No table property defined", type="PropertyNotDefined" );
		}
		if( isNull( variables.properties.autoCreate ) ){
			variables.properties.autoCreate = true;
		}
		if( isNull( variables.properties.dsn ) ){
			variables.properties.dsn = getDefaultDatasource();
		}
		if( isNull( variables.properties.schema ) ){
			variables.properties.schema = "";
		}

		// Build out table
		if( variables.properties.autoCreate ){
			ensureTable();
		}

		return this;
	}

    /**
     * Set a token in the storage
     *
     * @key The cache key
     * @token The token to store
     * @expiration The token expiration
     *
     * @return JWTStorage
     */
    any function set( required key, required token, required expiration ){
		queryExecute(
			"INSERT INTO #getTable()# (#variables.COLUMNS#)
				VALUES (
					:uuid,
					:cacheKey,
					:token,
					:expiration,
					:created
				)
			",
			{
				uuid      	= { cfsqltype="varchar", 	value="#variables.uuid.randomUUID().toString()#" },
				cacheKey  	= { cfsqltype="varchar", 	value=arguments.key },
				token  		= { cfsqltype="varchar", 	value=arguments.token },
				expiration 	= { cfsqltype="timestamp", 	value=arguments.expiration },
				created     = { cfsqltype="timestamp", 	value=now() }
			},
			{
				datasource = variables.properties.dsn
			}
		);
		return this;
	}

    /**
     * Verify if the passed in token key exists
     *
     * @key The cache key
     */
    boolean function exists( required key ){
		queryExecute(
			"INSERT INTO #getTable()# (#variables.COLUMNS#)
				VALUES (
					:uuid,
					:cacheKey,
					:token,
					:expiration,
					:created
				)
			",
			{
				uuid      	= { cfsqltype="varchar", 	value="#variables.uuid.randomUUID().toString()#" },
				cacheKey  	= { cfsqltype="varchar", 	value=arguments.key },
				token  		= { cfsqltype="varchar", 	value=arguments.token },
				expiration 	= { cfsqltype="timestamp", 	value=arguments.expiration },
				created     = { cfsqltype="timestamp", 	value=now() }
			},
			{
				datasource = variables.properties.dsn
			}
		);
	}

    /**
     * Retrieve the token via the cache key, if the key doesn't exist a TokenNotFoundException will be thrown
     *
     * @key The cache key
     * @defaultValue If not found, return a default value
     *
     * @throws TokenNotFoundException
     */
    struct function get( required key, struct defaultValue ){
		// select entry
		var q = queryExecute(
			"SELECT cacheKey, token, expiration, created
				FROM #getTable()#
				WHERE cacheKey = ?
			",
			[ arguments.key ],
			{
				datsource 	= variables.properties.dsn
			}
		);

		// Just return if records found, else null
		if( q.recordCount ){
			return {
				"token"      : q.token,
				"cacheKey"   : q.cacheKey,
				"expiration" : q.expiration,
				"created"    : q.created
			};
		}

		// Default value
		if( !isNull( arguments.defaultValue ) ){
			return arguments.defaultValue;
		}
	}

    /**
     * Invalidate/delete one or more keys from the storage
     *
     * @key A cache key or an array of keys to clear
     *
     * @return JWTStorage
     */
    any function clear( required any key ){
		queryExecute(
			"DELETE
			   FROM #getTable()#
			  WHERE cacheKey = ?
			",
			[ arguments.key ],
			{
				datsource 	= variables.properties.dsn,
				result 		= "local.q"
			}
		);

		return ( local.q.recordCount ? true : false );
	}

    /**
     * Clear all the keys in the storage
     *
     * @return JWTStorage
     */
    any function clearAll(){
		queryExecute(
			"TRUNCATE TABLE #getTable()#",
			{},
			{
				datsource 	= variables.properties.dsn
			}
		);

		return this;
	}

    /**
     * Retrieve all the jwt keys stored in the storage
     */
    array function keys(){
		var qResults = queryExecute(
			"SELECT cacheKey FROM #getTable()# ORDER BY cacheKey ASC",
			{},
			{
				datsource 	= variables.properties.dsn
			}
		);

		return (
			variables.isLucee ?
			queryColumnData( qResults, "cacheKey" ) :
			listToArray( valueList( qResults.cacheKey ) )
		);
	}

    /**
     * The size of the storage
     */
	numeric function size(){
		var q = queryExecute(
			"SELECT count( id ) as totalCount
			   FROM #getTable()#
			",
			{},
			{
				datsource 	= variables.properties.dsn
			}
		);

		return q.totalCount;
	}

	/******************************** PRIVATE ************************************/

	/**
	 * Get the default application datasource
	 */
	private string function getDefaultDatasource(){
		// get application metadata
	   var settings = getApplicationMetadata();

		// check orm settings first
		if( structKeyExists( settings, "ormsettings" ) AND structKeyExists( settings.ormsettings, "datasource" ) ){
			return settings.ormsettings.datasource;
		}

		// else default to app datasource
		if( !isNull( settings.datasource ) ){
			return settings.datasource;
		}

		throw(
			message="No default datasource defined and no dsn property found",
			type="PropertyNotDefined"
		);
	}

	/**
	 * Return the table name with the appropriate schema included if found.
	 */
	private function getTable(){
		if( len( variables.properties.schema ) ){
			return variables.properties.schema & "." & variables.properties.table;
		}
		return variables.properties.table;
	}

	/**
	 * Verify or create the logging table
	 */
	private function ensureTable(){
		var tableFound 		= false;
		var qCreate 		= "";
		var cols 			= variables.columns;

		if( variables.properties.autocreate ){
			// Get Tables on this DSN
			cfdbinfo( datasource="#variables.properties.dsn#", name="local.qTables", type="tables" );
			// Find the table
			for( var thisRecord in local.qTables ){
				if( thisRecord.table_name == variables.properties.table ){
					tableFound = true;
					break;
				}
			}
			// create it
			if( NOT tableFound ){
				queryExecute(
					"CREATE TABLE #getTable()# (
						id VARCHAR(36) NOT NULL,
						cacheKey VARCHAR(255) NOT NULL,
						expiration VARCHAR(255) NOT NULL,
						created #getDateTimeColumnType()# NOT NULL,
						token #getTextColumnType()# NOT NULL,
						PRIMARY KEY (id)
						KEY 'idx_cachekey' (cacheKey)
					)",
					{},
					{
						datasource = variables.properties.dsn
					}
				);
			}
		}
	}

	/**
	 * Get db specific text column type
	 */
	private function getTextColumnType(){
		var qResults = "";

		cfdbinfo( type="Version", name="qResults", datasource="#variables.properties.dsn#" );

		switch( qResults.database_productName ){
			case "PostgreSQL" : {
				return "TEXT";
			}
			case "MySQL" : {
				return "LONGTEXT";
			}
			case "Microsoft SQL Server" : {
				return "TEXT";
			}
			case "Oracle" :{
				return "LONGTEXT";
			}
			default : {
				return "TEXT";
			}
		}
	}

	/**
	 * Get db specific text column type
	 */
	private function getDateTimeColumnType(){
		var qResults = "";

		cfdbinfo( type="Version", name="qResults", datasource="#variables.properties.dsn#" );

		switch( qResults.database_productName ){
			case "PostgreSQL" : {
				return "TIMESTAMP";
			}
			case "MySQL" : {
				return "DATETIME";
			}
			case "Microsoft SQL Server" : {
				return "DATETIME";
			}
			case "Oracle" :{
				return "DATE";
			}
			default : {
				return "DATETIME";
			}
		}
	}

}