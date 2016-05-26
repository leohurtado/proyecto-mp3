import controlP5.*;
import ddf.minim.*;
import ddf.minim.analysis.*;
import java.util.*;
import java.net.InetAddress;
import javax.swing.*;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import org.elasticsearch.action.admin.indices.exists.indices.IndicesExistsResponse;
import org.elasticsearch.action.admin.cluster.health.ClusterHealthResponse;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.action.index.IndexResponse;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.action.search.SearchType;
import org.elasticsearch.client.Client;
import org.elasticsearch.common.settings.Settings;
import org.elasticsearch.node.Node;
import org.elasticsearch.node.NodeBuilder;

// Constantes para referir al nombre del indice y el tipo
static String INDEX_NAME = "canciones";
static String DOC_TYPE = "cancion";

ControlP5 cp5;
ScrollableList list;
Minim minim;
AudioPlayer song;
FFT fft;

boolean playing=false;
String path;
float volume=0;
AudioMetaData meta;
String [] paths;
int i=1;
//PFont font;

Client client;
Node node;

void setup() {
  size(530, 500);
  //font = loadFont("Arial.vlw");
  //textFont(font);
  cp5 = new ControlP5(this);
  paths = new String[120];
  minim = new Minim(this);
  // Configuracion basica para ElasticSearch en local
  Settings.Builder settings = Settings.settingsBuilder();
  // Esta carpeta se encontrara dentro de la carpeta del Processing
  settings.put("path.data", "esdata");
  settings.put("path.home", "/");
  settings.put("http.enabled", false);
  settings.put("index.number_of_replicas", 0);
  settings.put("index.number_of_shards", 1);

  // Inicializacion del nodo de ElasticSearch
  node = NodeBuilder.nodeBuilder()
          .settings(settings)
          .clusterName("mycluster")
          .data(true)
          .local(true)
          .node();

  // Instancia de cliente de conexion al nodo de ElasticSearch
  client = node.client();

  // Esperamos a que el nodo este correctamente inicializado
  ClusterHealthResponse r = client.admin().cluster().prepareHealth().setWaitForGreenStatus().get();
  println(r);

  // Revisamos que nuestro indice (base de datos) exista
  IndicesExistsResponse ier = client.admin().indices().prepareExists(INDEX_NAME).get();
  if(!ier.isExists()) {
    // En caso contrario, se crea el indice
    client.admin().indices().prepareCreate(INDEX_NAME).get();
  }

  // Agregamos a la vista un boton de importacion de archivos
  cp5.addButton("importFiles")
    .setPosition(320, height-40)
    .setSize(200,30)
    .setLabel("Importar archivos");
    
  cp5.addButton("pausa")
    .setPosition(320, height-80)
    .setSize(60,30)
    .setLabel("II");
    
  cp5.addButton("play")
    .setPosition(390, height-80)
    .setSize(60,30)
    .setLabel("|>");
  
  cp5.addButton("detener")
    .setPosition(460, height-80)
    .setSize(60,30)
    .setLabel("[]"); 
    
  cp5.addButton("mas")
    .setPosition(320, height-120)
    .setSize(60,30)
    .setLabel("+");
    
  cp5.addButton("menos")
    .setPosition(460, height-120)
    .setSize(60,30)
    .setLabel("-");  

  // Agregamos a la vista una lista scrollable que mostrara las canciones
  list = cp5.addScrollableList("playlist")
            .setPosition(10, height-120)
            .setSize(300, 119)
            .setBarHeight(20)
            .setItemHeight(20)
            .setType(ScrollableList.LIST);

  // Cargamos los archivos de la base de datos
  loadFiles();
}

void draw() {
  background(0);
  try {
    int timeleft=song.length()-song.position();
    meta = song.getMetaData();
    fill(#0431B4);
    textAlign(CENTER);
    textSize(20);
    text(meta.title(), width/2, height-230);
    textSize(14);
    text("Album: "+meta.album(), width/2, height-170);
    text(meta.author(), width/2, height-200);
    textSize(10);
    text("Tiempo : "+timeleft, width/2, height-150);
  }catch(Exception e) {}
  
  try{
    fft.forward( song.mix );
    for(int i = 0; i < fft.specSize(); i++){
    // draw the line for frequency band i, scaling it up a bit so we can see it
    //stroke();
    stroke(16+i,159-i,105*i);
    line( i, height/2, i, (height - fft.getBand(i)*8)/2);
    }
  } catch(Exception e){}
}

public void play() {
  if (playing==false){
    song.play();
    playing=true;
  }
}

public void pausa() {
  song.pause();
  playing=false;
}

public void detener(){
  song.pause();
  song.rewind();
  playing=false;
}

public void mas() {
  song.setGain(volume+=3);
}

public void menos() {
  song.setGain(volume-=3);
}

void importFiles() {
  // Selector de archivos
  JFileChooser jfc = new JFileChooser();
  // Agregamos filtro para seleccionar solo archivos .mp3
  jfc.setFileFilter(new FileNameExtensionFilter("MP3 File", "mp3"));
  // Se permite seleccionar multiples archivos a la vez
  jfc.setMultiSelectionEnabled(true);
  // Abre el dialogo de seleccion
  jfc.showOpenDialog(null);

  // Iteramos los archivos seleccionados
  for(File f : jfc.getSelectedFiles()) {
    // Si el archivo ya existe en el indice, se ignora
    GetResponse response = client.prepareGet(INDEX_NAME, DOC_TYPE, f.getAbsolutePath()).setRefresh(true).execute().actionGet();
    if(response.isExists()) {
      continue;
    }

    // Cargamos el archivo en la libreria minim para extrar los metadatos
    Minim minim = new Minim(this);
    AudioPlayer song = minim.loadFile(f.getAbsolutePath());
    AudioMetaData meta = song.getMetaData();

    // Almacenamos los metadatos en un hashmap
    Map<String, Object> doc = new HashMap<String, Object>();
    doc.put("author", meta.author());
    doc.put("title", meta.title());
    doc.put("path", f.getAbsolutePath());

    try {
      // Le decimos a ElasticSearch que guarde e indexe el objeto
      client.prepareIndex(INDEX_NAME, DOC_TYPE, f.getAbsolutePath())
        .setSource(doc)
        .execute()
        .actionGet();

      // Agregamos el archivo a la lista
      addItem(doc);
    } catch(Exception e) {
      e.printStackTrace();
    }
  }
}

// Al hacer click en algun elemento de la lista, se ejecuta este metodo
void playlist(int n) {
  println(list.getItem(n));
  path=paths[n+1];
  if (playing==false){
    song = minim.loadFile(path, 1024);
    fft = new FFT(song.bufferSize(), song.sampleRate());
  }
}

void loadFiles() {
  try {
    // Buscamos todos los documentos en el indice
    SearchResponse response = client.prepareSearch(INDEX_NAME).execute().actionGet();

    // Se itera los resultados
    for(SearchHit hit : response.getHits().getHits()) {
      // Cada resultado lo agregamos a la lista
      addItem(hit.getSource());
    }
  } catch(Exception e) {
    e.printStackTrace();
  }
}

// Metodo auxiliar para no repetir codigo
void addItem(Map<String, Object> doc) {
  // Se agrega a la lista. El primer argumento es el texto a desplegar en la lista, el segundo es el objeto que queremos que almacene
  list.addItem(doc.get("author") + " - " + doc.get("title"), doc);
  paths[i]=doc.get("path")+"";
  i+=1;
}
