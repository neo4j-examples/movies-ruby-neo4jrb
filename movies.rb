require 'sinatra'
require 'neo4j'
require 'neo4j/session_manager'

neo4j_url = ENV['NEO4J_URL'] || 'http://localhost:7474'

Neo4j::Core::CypherSession::Adaptors::Base.subscribe_to_query(&method(:puts))

adaptor_type = neo4j_url.match(/^bolt:/) ? :bolt : :http
Neo4j::ActiveBase.on_establish_session do
  Neo4j::SessionManager.open_neo4j_session(adaptor_type, neo4j_url)
end

session = Neo4j::ActiveBase.current_session

session.query('CREATE CONSTRAINT ON (m:Movie) ASSERT m.title IS UNIQUE')
session.query('CREATE CONSTRAINT ON (p:Person) ASSERT p.name IS UNIQUE')

require './models'

set :root, File.dirname(__FILE__)
set :public_folder, File.dirname(__FILE__) + '/static'

get '/' do
  send_file File.expand_path('index.html', settings.public_folder)
end

get '/graph' do
  actors = Person.all.to_a # or if we want to be sure, query_as(:p).match("p-[:ACTED_IN]->()").pluck('distinct p')
  movies = Movie.all.to_a

  nodes = actors + movies
  links = movies.map.with_index(2).to_a.map do |movie_and_index|
    movie_and_index[0].actors.map do |a|
      {source: movie_and_index[1], target: nodes.index(a)}
    end
  end.flatten

  nodes_hash = actors.map{|n| {title: n.name, label: "actor"}} + movies.map{|n| {title: n.title, label: "movie"}}

  {nodes: nodes_hash, links:links}.to_json
end

get '/search' do
  movies = Movie.where(title: /.*#{request['q']}.*/i)

  movies.map {|movie| {movie: movie.attributes} }.to_json
end

get '/movie/:title' do
  movie = Movie.where(title: params['title']).first

  cast_data_for_role = Proc.new do |role|
    Proc.new do |person, rel|
      {
        name: person.name,
        # we could have used the roles accessor (rel.roles) method here when rol is a Engagement class
        role: rel.props[:roles] || [],  
        job: role
      }
    end
  end

  cast_data = movie.actors.each_with_rel.map(&cast_data_for_role.call(:acted)) +
              movie.directors.each_with_rel.map(&cast_data_for_role.call(:directed))

  {title: movie.title, cast: cast_data}.to_json
end

