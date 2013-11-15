Ext.ns('Ung');
Ext.ns('Ung.Alpaca');
Ext.ns('Ung.Alpaca.Pages');
Ext.ns('Ung.Alpaca.Pages.Qos');

if ( Ung.Alpaca.Glue.hasPageRenderer( "qos", "index" )) {
    Ung.Alpaca.Util.stopLoading();
}

Ung.Alpaca.Pages.Qos.Index = Ext.extend( Ung.Alpaca.PagePanel, {
    initComponent : function()
    {
        this.priorityStore = [];
        this.priorityMap = {};

        Ung.Alpaca.Util.addToStoreMap( 10, this._( "High" ), this.priorityStore, this.priorityMap );
        Ung.Alpaca.Util.addToStoreMap( 20, this._( "Normal" ), this.priorityStore, this.priorityMap );
        Ung.Alpaca.Util.addToStoreMap( 30, this._( "Low" ), this.priorityStore, this.priorityMap );

        this.qosGrid = this.buildQosGrid();

        if ( Ung.Alpaca.isAdvanced ) {
            this.bandwidthLabel = new Ext.form.Label({
                xtype : "label",
                html : this._( "Uplink Bandwidth" ),
                cls: 'label-section-heading-2'                
            });

            this.bandwidthGrid = this.buildBandwidthGrid();
        }

        this.statisticsGrid = this.buildStatisticsGrid();
                
        var percentageStore = this.buildPercentageStore();
        
        var fieldsetItems = [{
            xtype : "checkbox",
            fieldLabel : this._( "Enabled" ),
            name : "qos_settings.enabled"
        }]

        if ( !Ung.Alpaca.isAdvanced ) {
            fieldsetItems = fieldsetItems.concat([{
                xtype : "numberfield",
                fieldLabel : this._( "Download Bandwidth" ),
                name : "bandwidth.0.download_bandwidth",
                boxLabel : this._( "kbps" )
            }]);
        }
        
        fieldsetItems = fieldsetItems.concat([{
            xtype : "combo",
            fieldLabel : this._( "Limit Download To" ),
            name : "qos_settings.download_percentage",
            mode : "local",
            triggerAction : "all",
            editable : false,
            width : 60,
            listWidth : 50,
            store : percentageStore
        }]);

        if ( !Ung.Alpaca.isAdvanced ) {
            fieldsetItems = fieldsetItems.concat([{
                xtype : "numberfield",
                fieldLabel : this._( "Upload Bandwidth" ),
                name : "bandwidth.0.upload_bandwidth",
                boxLabel : this._( "kbps" )
            }]);
        }
        
        fieldsetItems = fieldsetItems.concat([{
            xtype : "combo",
            fieldLabel : this._( "Limit Upload To" ),
            name : "qos_settings.upload_percentage",
            mode : "local",
            triggerAction : "all",
            editable : false,
            width : 60,
            listWidth : 50,
            store : percentageStore
        }]);

        var items = [{
            html : this._("QoS"),                
            xtype : "label",
            cls : "page-header-text"
        },{
            autoHeight : true,
            defaults : {
                xtype : "textfield",
                itemCls : 'label-width-2'                         
            },
            items : fieldsetItems
        }];
        
        items = items.concat([{
            autoHeight : true,
            defaults : {
                xtype : "textfield",
                itemCls : 'label-width-2'
            },
            items : [{
                xtype : "combo",
                fieldLabel : this._( "Ping Priority" ),
                name : "qos_settings.prioritize_ping",
                mode : "local",
                triggerAction : "all",
                editable : false,
                width : 70,
                listWidth : 60,
                store : this.priorityStore
            },{
                xtype : "combo",
                fieldLabel : this._( "ACK Priority" ),
                boxLabel : this._( "A High ACK Priority speeds up downloads while uploading" ),
                name : "qos_settings.prioritize_ack",
                mode : "local",
                triggerAction : "all",
                editable : false,
                width : 70,
                listWidth : 60,
                store : this.priorityStore
            },{
                xtype : "combo",
                fieldLabel : this._( "Gaming Priority" ),
                name : "qos_settings.prioritize_gaming",
                mode : "local",
                triggerAction : "all",
                editable : false,
                width : 70,
                listWidth : 60,
                store : this.priorityStore
            }]
        }]);

        if ( Ung.Alpaca.isAdvanced ) {                                                  
            items = items.concat([
                this.bandwidthLabel, 
                this.bandwidthGrid 
            ]);
        }
        
        items = items.concat([{
            xtype : "label",
            html : this._( "QoS Rules" ),
            cls: 'label-section-heading-2'                                
        }, this.qosGrid ]);
                
        items = items.concat([{
            xtype : "label",
            html : this._( "QoS Statistics" ),
            cls: 'label-section-heading-2'                                                
        }, this.statisticsGrid ]);
                     
        Ext.apply( this, {
            defaults : {
                xtype : "fieldset"
            },
            items : items
        });
        
        Ung.Alpaca.Pages.Qos.Index.superclass.initComponent.apply( this, arguments );
    },

    buildPercentageStore : function()
    {
        var percentageStore = [];
        percentageStore.push([ 100, "100%"]);
        percentageStore.push([ 95, "95%"]);

        for ( var c = 0 ; c < 9 ; c++ ) {
            var v = 100 - ( 10 * ( c + 1 ));
            percentageStore[c+2] = [ v, v + "%"  ];
        }

        return percentageStore;
    },

    buildQosGrid : function()
    {
        var enabledColumn = new Ung.Alpaca.grid.CheckColumn({
            header : this._( "On" ),
            dataIndex : 'enabled',
            sortable: false,
            fixed : true
        });

        var rowEditorConfig = {
            xtype: "roweditor",
            panelItems: [{
                xtype : "fieldset",
                autoHeight : true,
                items:[{
                    xtype: "checkbox",
                    fieldLabel : this._( "Enabled" ),
                    dataIndex: "enabled"
                },{
                    xtype: "textfield",
                    fieldLabel : this._( "Description" ),
                    dataIndex: "description",
                    width: 360
                },{
                    xtype : "combo",
                    fieldLabel : this._( "Priority" ),
                    dataIndex : "priority",
                    listWidth : 60,
                    editable : false,
                    width : 70,
                    triggerAction : "all",
                    mode : "local",
                    store : this.priorityStore
                }]
            },{
                xtype : "fieldset",
                autoWidth : true,
                autoScroll: true,
                autoHeight : true,
                title: "If all of the following conditions are met:",
                items : [{
                    xtype:"rulebuilder",
                    anchor:"98%",
                    dataIndex: "filter",
                    ruleInterfaceValues : this.settings["interface_enum"]
                }]
            }]
        };

        var qosGrid = new Ung.Alpaca.EditorGridPanel({
            settings : this.settings,

            recordFields : [ "id", "enabled", "description", "filter", "priority" ],
            selectable : true,
            sortable : false,
            hasReorder: true,
            hasEdit : true,
            rowEditorConfig : rowEditorConfig,
            
            name : "qos_rules",

            recordDefaults : {
                enabled : true,
                priority : 20,
                filter : "s-addr::",
                description : this._( "[New Entry]" )
            },
            
            plugins : [ enabledColumn ],

            columns : [ enabledColumn, {
                header : this._( "Priority" ),
                width: 70,
                sortable: false,
                fixed : true,
                dataIndex : "priority",
                renderer : function( value, metadata, record )
                {
                    return this.priorityMap[value];
                }.createDelegate( this ),
                editor : new Ext.form.ComboBox({
                    store : this.priorityStore,
                    listWidth : 60,
                    width : 70,
                    triggerAction : "all",
                    mode : "local",
                    editable : false
                })
            },{
                header : this._( "Description" ),
                width: 200,
                sortable: false,
                dataIndex : "description",
                editor : new Ext.form.TextField({
                    allowBlank : false 
                })
            }]
        });

        qosGrid.store.load();
        
        return qosGrid;
    },

    buildBandwidthGrid : function()
    {
        var bandwidthGrid = new Ung.Alpaca.EditorGridPanel({
            settings : this.settings,
            height : 100,
            recordFields : [ "name", "config_type", "os_name", "mac_address",
                             "index", "id", "upload_bandwidth", "download_bandwidth" ],
            selectable : false,
            sortable : false,
            hasReorder: false,
            hasEdit : false,
            tbar : [],
            
            name : "bandwidth",
                        
            columns : [{
                header : this._( "Name" ),
                width: 80,
                sortable: false,
                fixed : true,
                align : "center",
                dataIndex : "name"
            },{
                header : this._( "Config Type" ),
                width: 84,
                fixed : true,
                align : "center",
                sortable: false,
                dataIndex : "config_type",
                renderer : function( value, metadata, record ) { return value + this._( " (wan)" )}.createDelegate( this )
            },{
                header : this._( "Download Bandwidth" ),
                width: 84,
                dataIndex : "download_bandwidth",
                editor : new Ext.form.NumberField({
                    allowBlank : false 
                }),
                renderer : function( value, metadata, record ) { return value + this._( " kbps" )}.createDelegate( this )
            },{
                header : this._( "Upload Bandwidth" ),
                width: 84,
                dataIndex : "upload_bandwidth",
                editor : new Ext.form.NumberField({
                    allowBlank : false 
                }),
                renderer : function( value, metadata, record ) { return value + this._( " kbps" )}.createDelegate( this )
            }]
        });

        var store = bandwidthGrid.store;

        store.on( "update", this.updateTotalBandwidth, this );
        store.load();

        this.updateTotalBandwidth( store, null, null );

        return bandwidthGrid;
    },

    buildStatisticsGrid : function()
    {
        var store = new Ext.data.GroupingStore({
            proxy : new Ext.data.MemoryProxy( this.settings["status"] ),
            reader : new Ext.data.ArrayReader( {}, [{
                name :  "interface_name",
                mapping : "interface_name"
            },{
                name :  "priority",
                mapping : "priority"
            },{
                name : "rate",
                mapping : "rate"
            },{
                name : "burst",
                mapping : "burst"
            },{
                name : "sent",
                mapping : "sent"
            },{
                name : "tokens",
                mapping : "tokens"
            },{
                name : "ctokens",
                mapping : "ctokens"
            }]),
            groupField : "interface_name",
            sortInfo : { field : "priority", direction : "ASC" }
        });

        var view = new Ext.grid.GroupingView({
            forceFit : true,
            groupTextTpl : '{text}'
        });

        var statisticsGrid = new Ung.Alpaca.EditorGridPanel({
            settings : this.settings,

            store : store,
            view : view,
            selectable : false,
            sortable : true,
            saveData : false,
            
            name : "status",

            tbar : [{
                text : "Refresh",
                iconCls : 'icon-autorefresh',
                handler : this.refreshStatistics,
                scope : this
            }],

            columns : [{
                header : this._( "Interface" ),
                width: 55,
                hidden : true,
                sortable: true,
                dataIndex : "interface_name"
            },{
                id : "priority",
                header : this._( "Priority" ),
                width: 55,
                sortable: true,
                dataIndex : "priority"
            },{
                header : this._( "Rate" ),
                width: 75,
                sortable: true,
                dataIndex : "rate"
            },{
                header : this._( "Burst" ),
                width: 75,
                sortable: true,
                dataIndex : "burst"
            },{
                header : this._( "Sent" ),
                width: 75,
                sortable: true,
                dataIndex : "sent"
            },{
                header : this._( "Tokens" ),
                width: 75,
                sortable: true,
                dataIndex : "tokens"
            },{
                header : this._( "CTokens" ),
                width: 75,
                sortable: true,
                dataIndex : "ctokens"
            }]
        });

        statisticsGrid.store.load();
        return statisticsGrid;
    },

    saveMethod : "/qos/set_settings",

    refreshStatistics : function()
    {
        var handler = this.completeRefreshStatistics.createDelegate( this );
        Ung.Alpaca.Util.executeRemoteFunction( "/qos/get_statistics", handler );
    },

    completeRefreshStatistics : function( statistics, response, options )
    {
        if ( !statistics ) return;

        this.statisticsGrid.store.loadData( statistics );
    },

    updateTotalBandwidth : function( store, record, operation ) {
        var items = store.data.items;
        
        var u = 0;
        var d = 0;

        for ( var c = 0 ; c < items.length ; c++ ) {
            u += items[c].data.upload_bandwidth;
            d += items[c].data.download_bandwidth;
        }

        var message = String.format( this._( "Uplink Bandwidth ({0} kbps download, {1} kbps upload)" ),
                                     d, u );
        this.bandwidthLabel.setText( message );
    }
});

Ung.Alpaca.Pages.Qos.Index.settingsMethod = "/qos/get_settings";
Ung.Alpaca.Glue.registerPageRenderer( "qos", "index", Ung.Alpaca.Pages.Qos.Index );