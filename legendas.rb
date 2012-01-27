require 'rubygems'
require 'sinatra'
require 'rest-client'
require 'iconv'

configure do
  set :public_folder, Proc.new { File.join(root, "static") }
  enable :sessions
end

helpers do 
	def to_file(filme)
		if filme[:release].nil?
			return filme[:id]
		end
		nomeFilme = filme[:release] or filme[:titulo] or filme[:titulo_original]
		friendly_filename nomeFilme
	end
	def friendly_filename(filename)
	    filename.gsub(/[^\w\s_-]+/, '')
	            .gsub(/(^|\b\s)\s+($|\s?\b)/, '\\1\\2')
	            .gsub(/\s/, '_')
	end
end

get '/' do
	erb :legendas
end

post '/' do
	begin
		resultado = find({:filme => params[:filme], :cookies => session[:cookies]})
		@filmes = resultado[:filmes]
		session[:cookies] = resultado[:cookies]
		erb :legendas
	rescue
		puts $!.inspect, $@
		session[:cookies] = nil
		@erro = "Falha na consulta. Por favor tente novamente"
		erb :legendas
	end
end

get '/download/:id/:release' do
	legenda = download(params[:id], session[:cookies])
	content_type legenda.headers[:content_type]
	ext = legenda.headers[:content_type].include?("zip") ? ".zip" : ".rar"
	attachment friendly_filename(params[:release]) + ext
	legenda 
end

def find(findOptions)
	options = {:login => ENV['LOGIN'], :senha => ENV['PASSWORD'], :tipo => "1", :idioma => "1", :maximoPaginas => 20}.merge(findOptions)
	puts "Login com #{options[:login]} e #{options[:cookies]}"
	cookies = options[:cookies] or cookies = RestClient.post("http://legendas.tv/login_verificar.php", {:txtLogin => options[:login], :txtSenha => options[:senha]}).cookies
	puts "Cookies #{cookies}"
	linksEncontrados = []
	numeroPagina = 1
	buscaPage = RestClient.post("http://legendas.tv/index.php?opcao=buscarlegenda", {:txtLegenda => options[:filme], :selTipo => options[:tipo], :int_idioma => options[:idioma]}, {:cookies => cookies})
	begin
		buscaPage = RestClient.get("http://legendas.tv/index.php?opcao=buscarlegenda&pagina=0#{numeroPagina}", {:cookies => cookies}) if numeroPagina > 1
		buscaPageString = Iconv.new('UTF-8//IGNORE', 'UTF-8').iconv(buscaPage.to_str)
		linksEncontrados.concat(buscaPageString.scan(/abredown\('(.*?)'\)|gpop\('(.*?)','(.*?)','(.*?)','(.*?)','(.*?)','(.*?)','(.*?)','.+flag_(.*?)\.gif.*?','(.*?)'\)/))
		numeroPagina = numeroPagina + 1
	end until buscaPageString.scan(/pagina=0#{numeroPagina}/).empty? or numeroPagina > options[:maximoPaginas]
	
	filmes = Array.new
	if buscaPage.include?("Filmes com legendas") then
		filme = {}
		i = 0
		linksEncontrados.each do |item|
			if item[0].nil?
				i = i + 1
				filme = {}
				filme[:titulo_original] = item[1]
				filme[:titulo] = item[2]
				filme[:release] = item[3]
				filme[:cds] = item[4]
				filme[:fps] = item[5]
				filme[:tamanho] = item[6]
				filme[:downloads] = item[7]
				filme[:idioma] = item[8]
				filme[:data] = item[9]
				filmes << filme
			else
				filme[:id] = item[0]
				filme[:i] = i 
			end
		end
	elsif not buscaPage.include?("Nenhuma legenda foi encontrada")
		puts buscaPage
		raise "Pagina desconhecida"
	end	
	{:cookies => cookies, :filmes => filmes}
end

def download(id, cookies)
	RestClient.get("http://legendas.tv/info.php?d=#{id}&c=1", {:cookies => cookies, :raw_response => true})
end