const test=require('node:test');
const assert=require('node:assert/strict');
require('../Sources/ArchitectureGraph/Resources/c4-objects.js');

test('selects object components from typed evidence within the C4 kind',()=>{
  function role(kind,type){
    return C4Objects.resolve({kind,name:'Database service',attributes:{'context.catalogType':type}});
  }
  for(const [type,expected] of Object.entries({service:'service',website:'webApp','mobile-app':'mobileApp',worker:'worker','api-gateway':'gateway'})){
    assert.equal(role('application',type),expected);
    assert.equal(role('dataStore',type),'dataStore');
  }
  for(const [type,expected] of Object.entries({database:'database',cache:'cache',queue:'messageQueue','object-storage':'objectStorage'})){
    assert.equal(role('dataStore',type),expected);
    assert.equal(role('softwareSystem',type),expected);
    assert.equal(role('application',type),'application');
  }
  for(const kind of ['person','softwareSystem','dataArtifact','application','dataStore'])assert.equal(role(kind),kind);
  assert.equal(role('unclassified','database'),'unknown');
});
