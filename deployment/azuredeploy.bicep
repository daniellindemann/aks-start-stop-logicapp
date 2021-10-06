@description('Id of the service principal that executes the Azure actions')
param servicePrincipalClientId string

@description('Secret of the service principal that executes the Azure actions')
@secure()
param servicePrincipalClientSecret string

@description('Timezone the logic app works with (see https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones)')
param timeZone string = 'W. Europe Standard Time'

@description('Start date of the Logic Apps to check the AKS clusters')
param recurrenceStartDate string = utcNow('yyyy-MM-dd')

@description('Days to check for business hours')
param defaultBusinessHourDays string = 'Mon,Tue,Wed,Thu,Fri'

@description('Azure tag to check for business hour days on an AKS resource')
param defaultTagBusinessHoursDays string = 'Business Hours Days'

@description('Azure tag to check for business hours end on an AKS resource')
param defaultTagBusinessHoursEnd string = 'Business Hours End'

@description('Azure tag to check for business hours start on an AKS resource')
param defaultTagBusinessHoursStart string = 'Business Hours Start'

var location = resourceGroup().location
var subscriptionId = subscription().id
var tenantId = subscription().tenantId

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var reccurenceIntervalMinutes = 15
var resourceTags = {
  Version: '1.0.0'
  Subscription: subscription().subscriptionId
}

resource connection_arm 'Microsoft.Web/connections@2016-06-01' = {
  name: 'con-arm-${suffix}'
  location: location
  tags: resourceTags
  properties: {
    displayName: 'con-arm-${suffix}'
    parameterValues: {
      'token:clientId': servicePrincipalClientId
      'token:clientSecret': servicePrincipalClientSecret
      'token:TenantId': tenantId
      'token:grantType': 'client_credentials'
    }
    api: {
      id: '${subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/arm'
    }
  }
}

resource la_aksStart 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-aks-start-${suffix}'
  location: location
  tags: resourceTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        DefaultBusinessHourDays: {
          defaultValue: defaultBusinessHourDays
          type: 'String'
        }
        DefaultTagBusinessHoursDays: {
          defaultValue: defaultTagBusinessHoursDays
          type: 'String'
        }
        DefaultTagBusinessHoursEnd: {
          defaultValue: defaultTagBusinessHoursEnd
          type: 'String'
        }
        DefaultTagBusinessHoursStart: {
          defaultValue: defaultTagBusinessHoursStart
          type: 'String'
        }
        TimeZone: {
          defaultValue: timeZone
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: reccurenceIntervalMinutes
            startTime: '${recurrenceStartDate}T00:00:02Z'
            timeZone: timeZone
          }
          recurrence: {
            frequency: 'Minute'
            interval: reccurenceIntervalMinutes
            startTime: '${recurrenceStartDate}T00:00:02Z'
            timeZone: timeZone
          }
          type: 'Recurrence'
        }
      }

      actions: {
        Current_time_UTC: {
          inputs: {}
          kind: 'CurrentTime'
          runAfter: {}
          type: 'Expression'
        }
        For_each_AKS_cluster: {
          actions: {
            Condition: {
              actions: {
                AKS_Id_info: {
                  inputs: '@split(body(\'Parse_AKS_data\')?[\'id\'], \'/\')'
                  runAfter: {}
                  type: 'Compose'
                }
                Check_if_AKS_cluster_should_be_started: {
                  actions: {
                    Start_AKS_cluster: {
                      inputs: {
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
                          }
                        }
                        method: 'post'
                        path: '/subscriptions/@{encodeURIComponent(outputs(\'AKS_Id_info\')[2])}/resourcegroups/@{encodeURIComponent(outputs(\'AKS_Id_info\')[4])}/providers/@{encodeURIComponent(outputs(\'AKS_Id_info\')[6])}/@{encodeURIComponent(outputs(\'AKS_Id_info\')[7],\'/\',outputs(\'AKS_Id_info\')[8])}/@{encodeURIComponent(\'start\')}'
                        queries: {
                          'x-ms-api-version': '2021-05-01'
                        }
                      }
                      runAfter: {}
                      type: 'ApiConnection'
                    }
                  }
                  expression: {
                    and: [
                      {
                        greaterOrEquals: [
                          '@body(\'Local_time\')'
                          '@formatDateTime(body(\'Current_time_UTC\'), concat(\'yyyy-MM-ddT\', outputs(\'Get_Business_Hours_Start\'), \':00Z\'))'
                        ]
                      }
                      {
                        less: [
                          '@body(\'Local_time\')'
                          '@formatDateTime(body(\'Current_time_UTC\'), concat(\'yyyy-MM-ddT\', outputs(\'Get_Business_Hours_End\'), \':00Z\'))'
                        ]
                      }
                      {
                        contains: [
                          '@outputs(\'Get_Business_Hours_Days\')'
                          '@outputs(\'Current_day\')'
                        ]
                      }
                      {
                        not: {
                          equals: [
                            '@outputs(\'Get_Power_state\')'
                            'Running'
                          ]
                        }
                      }
                      {
                        equals: [
                          '@outputs(\'Get_Provisioning_state\')'
                          'Succeeded'
                        ]
                      }
                    ]
                  }
                  runAfter: {
                    Get_Provisioning_state: [
                      'Succeeded'
                    ]
                  }
                  type: 'If'
                }
                Get_AKS_resource: {
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
                      }
                    }
                    method: 'get'
                    path: '/subscriptions/@{encodeURIComponent(outputs(\'AKS_Id_info\')[2])}/resourcegroups/@{encodeURIComponent(outputs(\'AKS_Id_info\')[4])}/providers/@{encodeURIComponent(outputs(\'AKS_Id_info\')[6])}/@{encodeURIComponent(outputs(\'AKS_Id_info\')[7],\'/\',outputs(\'AKS_Id_info\')[8])}'
                    queries: {
                      'x-ms-api-version': '2021-05-01'
                    }
                  }
                  runAfter: {
                    AKS_Id_info: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                }
                Get_Power_state: {
                  inputs: '@body(\'Get_AKS_resource\')?[\'properties\']?[\'powerState\']?[\'code\']'
                  runAfter: {
                    Get_AKS_resource: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                }
                Get_Provisioning_state: {
                  inputs: '@body(\'Get_AKS_resource\')?[\'properties\']?[\'provisioningState\']'
                  runAfter: {
                    Get_Power_state: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                }
              }
              expression: {
                and: [
                  {
                    not: {
                      equals: [
                        '@outputs(\'Get_Business_Hours_Start\')'
                        '@null'
                      ]
                    }
                  }
                  {
                    not: {
                      equals: [
                        '@outputs(\'Get_Business_Hours_End\')'
                        '@null'
                      ]
                    }
                  }
                ]
              }
              runAfter: {
                Current_day: [
                  'Succeeded'
                ]
              }
              type: 'If'
            }
            Current_day: {
              inputs: '@formatDateTime(body(\'Local_time\'), \'ddd\')'
              runAfter: {
                Get_Business_Hours_Days: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_Days: {
              inputs: '@coalesce(body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursDays\')], parameters(\'DefaultBusinessHourDays\'))'
              runAfter: {
                Get_Business_Hours_End: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_End: {
              inputs: '@body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursEnd\')]'
              runAfter: {
                Get_Business_Hours_Start: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_Start: {
              inputs: '@body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursStart\')]'
              runAfter: {
                Parse_AKS_data: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Parse_AKS_data: {
              inputs: {
                content: '@items(\'For_each_AKS_cluster\')'
                schema: {
                  properties: {
                    id: {
                      type: 'string'
                    }
                    location: {
                      type: 'string'
                    }
                    name: {
                      type: 'string'
                    }
                    tags: {
                      type: 'object'
                    }
                    type: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
              }
              runAfter: {}
              type: 'ParseJson'
            }
          }
          foreach: '@body(\'Get_AKS_Clusters_in_subscription\')?[\'value\']'
          runAfter: {
            Get_AKS_Clusters_in_subscription: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Get_AKS_Clusters_in_subscription: {
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '${subscriptionId}/resources'
            queries: {
              '$filter': 'resourceType eq \'Microsoft.ContainerService/managedClusters\''
              'x-ms-api-version': '2016-06-01'
            }
          }
          runAfter: {
            Local_time: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
        }
        Local_time: {
          inputs: {
            baseTime: '@body(\'Current_time_UTC\')'
            destinationTimeZone: '@parameters(\'TimeZone\')'
            formatString: 'o'
            sourceTimeZone: 'UTC'
          }
          kind: 'ConvertTimeZone'
          runAfter: {
            Current_time_UTC: [
              'Succeeded'
            ]
          }
          type: 'Expression'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          arm: {
            connectionId: '${connection_arm.id}'
            connectionName: '${connection_arm.name}'
            id: '${connection_arm.properties.api.id}'
          }
        }
      }
    }
  }
}

resource la_aksStop 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-aks-stop-${suffix}'
  location: location
  tags: resourceTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        DefaultBusinessHourDays: {
          defaultValue: defaultBusinessHourDays
          type: 'String'
        }
        DefaultTagBusinessHoursDays: {
          defaultValue: defaultTagBusinessHoursDays
          type: 'String'
        }
        DefaultTagBusinessHoursEnd: {
          defaultValue: defaultTagBusinessHoursEnd
          type: 'String'
        }
        DefaultTagBusinessHoursStart: {
          defaultValue: defaultTagBusinessHoursStart
          type: 'String'
        }
        TimeZone: {
          defaultValue: timeZone
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: reccurenceIntervalMinutes
            startTime: '${recurrenceStartDate}T00:00:02Z'
            timeZone: timeZone
          }
          recurrence: {
            frequency: 'Minute'
            interval: reccurenceIntervalMinutes
            startTime: '${recurrenceStartDate}T00:00:02Z'
            timeZone: timeZone
          }
          type: 'Recurrence'
        }
      }

      actions: {
        Current_time_UTC: {
          inputs: {}
          kind: 'CurrentTime'
          runAfter: {}
          type: 'Expression'
        }
        For_each_AKS_cluster: {
          actions: {
            Condition: {
              actions: {
                AKS_Id_info: {
                  inputs: '@split(body(\'Parse_AKS_data\')?[\'id\'], \'/\')'
                  runAfter: {}
                  type: 'Compose'
                }
                Check_if_AKS_cluster_should_be_stopped: {
                  actions: {
                    Stop_AKS_cluster: {
                      inputs: {
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
                          }
                        }
                        method: 'post'
                        path: '/subscriptions/@{encodeURIComponent(outputs(\'AKS_Id_info\')[2])}/resourcegroups/@{encodeURIComponent(outputs(\'AKS_Id_info\')[4])}/providers/@{encodeURIComponent(outputs(\'AKS_Id_info\')[6])}/@{encodeURIComponent(outputs(\'AKS_Id_info\')[7],\'/\',outputs(\'AKS_Id_info\')[8])}/@{encodeURIComponent(\'stop\')}'
                        queries: {
                          'x-ms-api-version': '2021-05-01'
                        }
                      }
                      runAfter: {}
                      type: 'ApiConnection'
                    }
                  }
                  expression: {
                    and: [
                      {
                        or: [
                          {
                            greaterOrEquals: [
                              '@body(\'Local_time\')'
                              '@formatDateTime(body(\'Current_time_UTC\'), concat(\'yyyy-MM-ddT\', outputs(\'Get_Business_Hours_End\'), \':00Z\'))'
                            ]
                          }
                          {
                            less: [
                              '@body(\'Local_time\')'
                              '@formatDateTime(body(\'Current_time_UTC\'), concat(\'yyyy-MM-ddT\', outputs(\'Get_Business_Hours_Start\'), \':00Z\'))'
                            ]
                          }
                        ]
                      }
                      {
                        contains: [
                          '@outputs(\'Get_Business_Hours_Days\')'
                          '@outputs(\'Current_day\')'
                        ]
                      }
                      {
                        not: {
                          equals: [
                            '@outputs(\'Get_Power_state\')'
                            'Stopped'
                          ]
                        }
                      }
                      {
                        equals: [
                          '@outputs(\'Get_Provisioning_state\')'
                          'Succeeded'
                        ]
                      }
                    ]
                  }
                  runAfter: {
                    Get_Provisioning_state: [
                      'Succeeded'
                    ]
                  }
                  type: 'If'
                }
                Get_AKS_resource: {
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
                      }
                    }
                    method: 'get'
                    path: '/subscriptions/@{encodeURIComponent(outputs(\'AKS_Id_info\')[2])}/resourcegroups/@{encodeURIComponent(outputs(\'AKS_Id_info\')[4])}/providers/@{encodeURIComponent(outputs(\'AKS_Id_info\')[6])}/@{encodeURIComponent(outputs(\'AKS_Id_info\')[7],\'/\',outputs(\'AKS_Id_info\')[8])}'
                    queries: {
                      'x-ms-api-version': '2021-05-01'
                    }
                  }
                  runAfter: {
                    AKS_Id_info: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                }
                Get_Power_state: {
                  inputs: '@body(\'Get_AKS_resource\')?[\'properties\']?[\'powerState\']?[\'code\']'
                  runAfter: {
                    Get_AKS_resource: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                }
                Get_Provisioning_state: {
                  inputs: '@body(\'Get_AKS_resource\')?[\'properties\']?[\'provisioningState\']'
                  runAfter: {
                    Get_Power_state: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                }
              }
              expression: {
                and: [
                  {
                    not: {
                      equals: [
                        '@outputs(\'Get_Business_Hours_Start\')'
                        '@null'
                      ]
                    }
                  }
                  {
                    not: {
                      equals: [
                        '@outputs(\'Get_Business_Hours_End\')'
                        '@null'
                      ]
                    }
                  }
                ]
              }
              runAfter: {
                Current_day: [
                  'Succeeded'
                ]
              }
              type: 'If'
            }
            Current_day: {
              inputs: '@formatDateTime(body(\'Local_time\'), \'ddd\')'
              runAfter: {
                Get_Business_Hours_Days: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_Days: {
              inputs: '@coalesce(body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursDays\')], parameters(\'DefaultBusinessHourDays\'))'
              runAfter: {
                Get_Business_Hours_End: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_End: {
              inputs: '@body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursEnd\')]'
              runAfter: {
                Get_Business_Hours_Start: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Get_Business_Hours_Start: {
              inputs: '@body(\'Parse_AKS_data\')?[\'tags\']?[parameters(\'DefaultTagBusinessHoursStart\')]'
              runAfter: {
                Parse_AKS_data: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Parse_AKS_data: {
              inputs: {
                content: '@items(\'For_each_AKS_cluster\')'
                schema: {
                  properties: {
                    id: {
                      type: 'string'
                    }
                    location: {
                      type: 'string'
                    }
                    name: {
                      type: 'string'
                    }
                    tags: {
                      type: 'object'
                    }
                    type: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
              }
              runAfter: {}
              type: 'ParseJson'
            }
          }
          foreach: '@body(\'Get_AKS_Clusters_in_subscription\')?[\'value\']'
          runAfter: {
            Get_AKS_Clusters_in_subscription: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Get_AKS_Clusters_in_subscription: {
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'arm\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '${subscriptionId}/resources'
            queries: {
              '$filter': 'resourceType eq \'Microsoft.ContainerService/managedClusters\''
              'x-ms-api-version': '2016-06-01'
            }
          }
          runAfter: {
            Local_time: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
        }
        Local_time: {
          inputs: {
            baseTime: '@body(\'Current_time_UTC\')'
            destinationTimeZone: '@parameters(\'TimeZone\')'
            formatString: 'o'
            sourceTimeZone: 'UTC'
          }
          kind: 'ConvertTimeZone'
          runAfter: {
            Current_time_UTC: [
              'Succeeded'
            ]
          }
          type: 'Expression'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          arm: {
            connectionId: '${connection_arm.id}'
            connectionName: '${connection_arm.name}'
            id: '${connection_arm.properties.api.id}'
          }
        }
      }
    }
  }
}

output connection_arm_id string = connection_arm.id
output connection_type_id string = connection_arm.properties.api.id
