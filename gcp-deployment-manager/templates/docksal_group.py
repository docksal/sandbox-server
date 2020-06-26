def generate_config(context):
    properties = context.properties
    resource_name = 'mig-' + context.env['name']
    project = context.env['project']
    zone = properties['zone']
    template_id = properties['templateId']
    instance_template = 'projects/' + project + '/global/instanceTemplates/' + template_id

    outputs = []
    resources = [{
        'name': resource_name,
        'type': 'gcp-types/compute-v1:instanceGroupManagers',
        'properties': {
            'instanceTemplate': instance_template,
            'name': resource_name,
            'zone': zone,
            'targetSize': 1,
            'updatePolicy': {
                'maxSurge': {
                    'calculated': 0,
                    'fixed': 0
                },
                'maxUnavailable': {
                    'calculated': 1,
                    'fixed': 1
                },
                'minReadySec': 0,
                'minimalAction': 'REPLACE',
                'replacementMethod': 'RECREATE',
                'type': 'PROACTIVE'
            }
        }
    }]

    return {'resources': resources, 'outputs': outputs}
