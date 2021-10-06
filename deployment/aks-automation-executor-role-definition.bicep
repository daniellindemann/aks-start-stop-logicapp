targetScope = 'subscription'

param roleGuid string = guid('aks-automation-executor')

var subscriptionId = subscription().id
var roleName = 'Azure Kubernetes Service Automation Executor'

resource aks_automation_role 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' = {
  name: roleGuid
  properties: {
    roleName: roleName
    description: 'Allows to list, start and stop AKS clusters'
    assignableScopes: [
      subscriptionId
    ]
    permissions: [
      {
        actions: [
          'Microsoft.ContainerService/managedClusters/read'
          'Microsoft.ContainerService/managedClusters/start/action'
          'Microsoft.ContainerService/managedClusters/stop/action'
        ]
        dataActions: []
        notActions: []
        notDataActions: []
      }
    ]
  }
}





// {
//     "properties": {
//         "roleName": "Test AKS Automation Executor",
//         "description": "Allows to start and stop AKS clusters",
//         "assignableScopes": [
//             "/subscriptions/63d3cb88-9621-46c0-b611-36e23c5b402d"
//         ],
//         "permissions": [
//             {
//                 "actions": [
//                     "Microsoft.ContainerService/managedClusters/start/action",
//                     "Microsoft.ContainerService/managedClusters/stop/action",
//                     "Microsoft.ContainerService/managedClusters/read"
//                 ],
//                 "notActions": [],
//                 "dataActions": [],
//                 "notDataActions": []
//             }
//         ]
//     }
// }

