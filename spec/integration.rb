require 'rubygems'
require 'hpricot'
require 'net/http'
GIFTSMAS_ENV = :test
require 'models'

HOST = 'localhost'
PORT = 9571

module Hpricot::Traverse
  alias ih inner_html
  alias it inner_text
  def hc
    children.reject{|x| Hpricot::Text === x}
  end
  def titleh
    self.at(:title).ih
  end
end
class Hpricot::Elements
  def mapatt(att)
    collect{|x| x[att]}
  end
  def mapm(meth)
    collect{|x| x.send(meth)}
  end
  def maphr
    mapatt(:href)
  end
  def mapit
    mapm(:it)
  end
  def mapih
    mapm(:ih)
  end
  def maptype
    mapm(:name)
  end
  def mapinputtype
    mapatt(:type)
  end
  def mapname
    mapatt(:name)
  end
  def mapaction
    mapatt(:action)
  end
  def mapvalue
    mapatt(:value)
  end
  def mapmultiple
    mapatt(:multiple)
  end
  def mapmethod
    mapatt(:method)
  end
  def mapcaption
    map{|x| x.at(:caption).it}
  end
end

class Spec::Example::ExampleGroup
  def http_url(path)
    "http://#{HOST}:#{PORT}#{path}"
  end

  def content(path, params={})
    p = page(path, params)
    title = params.delete(:title)
    p.titleh.should == "Giftsmas - #{title}" if title
    p.at("div#content")
  end

  def page(path, params={})
    Hpricot(get(path, params).body)
  end

  def post(path, params={})
    request(path, params.merge(:post=>true))
  end

  def request(path, params={})
    req = (params.delete(:post) ? Net::HTTP::Post : Net::HTTP::Get).new(path)
    if params.delete(:xhr)
      req['Accept'] = "text/javascript, text/html, application/xml, text/xml, */*"
      req['X-Requested-With'] = 'XMLHttpRequest'
    end
    if session = params.delete(:session)
      session.set_header(req)
    end
    req.set_form_data(params)
    Net::HTTP.new(HOST, PORT).start do |http|
      res = http.request(req)
      session.get_header(res) if session
      res
    end
  end
  alias get request

  def create_user(name)
    User.create(:name=>name, :password=>'valid')
  end

  def sign_in(user)
    create_user(user)
    session = SpecSession.new
    post('/login', 'user'=>user, 'password'=>'valid', :session=>session)
    post('/add_event', :session=>session, 'name'=>'Christmas')
    session
  end

  def delete_tables(*tables)
    tables.each{|t| DB[t].delete}
  end
end

class SpecSession
  attr_reader :session

  def set_header(request)
    request['Cookie'] = @session if @session
  end
  
  def get_header(response)
    if cookie = response['Set-Cookie']
      @session = cookie.gsub(/; path=\/\z/, '')
    end
  end
end

context "Giftsmas" do
  after do
    delete_tables(:gift_senders, :gift_receivers, :event_senders, :event_receivers, :gifts, :events, :people, :users)
  end

  specify "should redirect all pages except /login and /logout to /login if the user hasn't logged in" do
    get('/')['Location'].should == '/login'
    get('/choose_event')['Location'].should == '/login'
    get('/manage')['Location'].should == '/login'
  end

  specify "/login should render the login page" do
    p = page('/login')
    c = p.at("div#content")
    forms = c/:form
    forms.length.should == 1
    form = forms.first
    form[:action].should == '/login'
    form[:method].should == 'post'
    inputs = form/:input
    inputs.mapname.should == ['user', 'password', nil]
    inputs.mapinputtype.should == %w'text password submit'
    n = p.at("div#nav")
    as = n/:a
    as.maphr.should == %w'/'
    as.mapit.should == %w'Giftsmas'
  end

  specify "should handle the login process: /login->/choose_event->/" do
    create_user('jeremy')
    session = SpecSession.new
    get('/', :session=>session)['Location'].should == '/login'
    content('/login', :title=>'Login')
    post('/login', :session=>session, 'user'=>'jeremy', 'password'=>'valid')['Location'].should == '/choose_event'

    p = page('/choose_event', :session=>session)
    p.titleh.should == "Giftsmas - Create Your Event"

    c = p.at("div#content")
    forms = c/:form
    forms.length.should == 1
    form = forms.first
    form[:action].should == '/add_event'
    form[:method].should == 'post'
    inputs = form/:input
    inputs.mapname.should == ['name', nil]
    inputs.mapinputtype.should == %w'text submit'
    post('/add_event', :session=>session, inputs.first[:name]=>'Christmas')['Location'].should == '/'

    p = page('/', :session=>session)
    c = p.at("div#content")
    forms = c/:form
    forms.length.should == 1
    form = forms.first
    form[:action].should == '/add_gift'
    form[:method].should == 'post'
    inputs = form/:input
    inputs.mapname.should == ['gift', 'new_senders', 'new_receivers', nil]
    inputs.mapinputtype.should == %w'text text text submit'
    n = p.at("div#nav")
    (n/:h4).mapih.should == ['Event: Christmas', 'Gift Reports', 'Other']
    as = n/:a
    eid = Event.first.id
    as.maphr.should == ["/", "/manage/edit_event_receivers/#{eid}", "/manage/edit_event_senders/#{eid}", "/choose_event", "/reports/chronological", "/reports/by_receiver", "/reports/by_sender", "/reports/summary", "/reports/crosstab", "/manage/manage_event", "/manage/manage_gift", "/manage/manage_person"]
    as.mapit.should == ["Giftsmas", "Associate Receivers", "Associate Senders", "Change Event", "In Chronological Order", "By Receiver", "By Sender", "Summary", "Summary Crosstab", "Manage Events", "Manage Gifts", "Manage People"]
  end

  specify "/add_gift should add gifts correctly" do
    session = sign_in('jeremy')
    Gift.count.should == 0
    post('/add_gift', :session=>session, 'gift'=>'Gift1', 'new_senders'=>'Person1', 'new_receivers'=>'Person2')['Location'].should == '/'
    Gift.count.should == 1
    gift = Gift.first
    gift.name.should == 'Gift1'
    gift.senders.map{|x| x.name}.should == %w'Person1'
    gift.receivers.map{|x| x.name}.should == %w'Person2'

    c = content('/', :title=>'Add Gift', :session=>session)
    (c/:h4).mapih.should == ['Gift Added: Gift1<br />Senders: Person1<br />Receivers: Person2']
    forms = c/:form
    forms.length.should == 1
    form = forms.first
    form[:action].should == '/add_gift'
    form[:method].should == 'post'
    inputs = form/:input
    inputs.mapname.should == ['gift', 'new_senders', 'new_receivers', nil]
    inputs.mapinputtype.should == %w'text text text submit'
    selects = form/:select
    selects.mapname.should == %w'senders receivers'
    selects.mapmultiple.should == %w'multiple multiple'
    p1id = Person[:name=>'Person1'].id.to_s
    p2id = Person[:name=>'Person2'].id.to_s
    (selects.first/:option).mapit.should == ['Person1']
    (selects.first/:option).mapvalue.should == [p1id]
    (selects.last/:option).mapit.should == ['Person2']
    (selects.last/:option).mapvalue.should == [p2id]
    post('/add_gift', :session=>session, 'gift'=>'Gift2', 'new_senders'=>'Person3,Person4', 'new_receivers'=>'Person5, Person6', 'senders'=>p1id, 'receivers'=>p2id)['Location'].should == '/'

    c = content('/', :session=>session)
    Gift.count.should == 2
    gift = Gift[:name=>'Gift2']
    gift.name.should == 'Gift2'
    gift.senders.map{|x| x.name}.should == %w'Person1 Person3 Person4'
    gift.receivers.map{|x| x.name}.should == %w'Person2 Person5 Person6'
    selects = c/:select
    pids = Person.order(:name).map(:id).map{|x| x.to_s}
    (selects.first/:option).mapit.should == %w'Person1 Person3 Person4'
    (selects.first/:option).mapvalue.should == pids[0..0] + pids[2..3]
    (selects.last/:option).mapit.should == %w'Person2 Person5 Person6'
    (selects.last/:option).mapvalue.should == pids[1..1] + pids[4..5]
  end

  specify "/choose_event should change the current event" do
    session = sign_in('jeremy')
    e1 = Event.first
    e2 = Event.create(:user_id=>User.first.id, :name=>'Birthday')
    c = content('/choose_event', :title=>'Choose Your Event', :session=>session)
    (c/:h2).mapit.should == ['Choose an Existing Event', 'Create a New Event']
    forms = c/:form
    forms.mapaction.should == %w'/choose_event /add_event'
    forms.mapmethod.should == %w'post post'
    form = forms.first
    selects = form/:select
    selects.mapname.should == %w'event_id'
    (selects.first/:option).mapit.should == %w'Birthday Christmas'
    (selects.first/:option).mapvalue.should == [e2.id.to_s, e1.id.to_s]
    inputs = form/:input
    inputs.mapname.should == [nil]
    inputs.mapinputtype.should == %w'submit'
    post('/choose_event', :session=>session, 'event_id'=>e2.id.to_s)['Location'].should == '/'
    page('/', :session=>session).at("#nav h4").it.should == "Event: Birthday"
  end

  specify "/logout should log the user out" do
    session = sign_in('jeremy')
    post('/logout', :session=>session)['Location'].should == '/login'
    get('/')['Location'].should == '/login'
  end

  specify "scaffolded forms should be available" do
    session = sign_in('jeremy')
    eid = Event.first.id.to_s
    content("/manage/edit_event_receivers/#{eid}", :title=>"Update Christmas's receivers", :session=>session)
    content("/manage/edit_event_senders/#{eid}", :title=>"Update Christmas's senders", :session=>session)
    %w'event gift person'.each do |x|
      %w'manage browse new delete edit merge search show'.each do |y|
        content("/manage/#{y}_#{x}", :session=>session).at(:h1).should_not == nil
      end
    end
  end

  specify "reports should be correct" do
    session = sign_in('jeremy')
    e = Event.first
    p1, p2, p3, p4, p5 = [1, 2, 3, 4, 5].collect{|x| Person.create(:user_id=>e.user_id, :name=>"P#{x}")}
    g1 = Gift.create(:event_id=>e.id, :name=>'G1')
    g1.add_sender(p1)
    g1.add_receiver(p2)
    g2 = Gift.create(:event_id=>e.id, :name=>'G2')
    g2.add_sender(p1)
    g2.add_receiver(p2)
    g3 = Gift.create(:event_id=>e.id, :name=>'G3')
    g3.add_sender(p1)
    g3.add_sender(p3)
    g3.add_receiver(p4)
    g4 = Gift.create(:event_id=>e.id, :name=>'G4')
    g4.add_sender(p3)
    g4.add_receiver(p2)
    g4.add_receiver(p4)

    c = content('/reports/chronological', :title=>'Gifts in Chronological Order', :session=>session)
    tables = c/:table
    tables.length.should == 1
    table = tables.first
    (table/:th).mapit.should == %w'Time Gift Senders Receivers'
    (table/"tbody tr").map{|x| (x/:td).mapit[1..-1]}.should == [%w'G1 P1 P2', %w'G2 P1 P2', ['G3', 'P1, P3', 'P4'], ['G4', 'P3', 'P2, P4']]

    c = content('/reports/by_receiver', :title=>'Gifts by Receiver', :session=>session)
    tables = c/:table
    tables.mapcaption.should == %w'P2 P4'
    table = tables.first
    (table/:th).mapit.should == ['Time', 'Gift', 'Senders', 'Other Receivers']
    (table/"tbody tr").map{|x| (x/:td).mapit[1..-1]}.should == [['G1', 'P1', ''], ['G2', 'P1', ''], %w'G4 P3 P4']
    table = tables.last
    (table/:th).mapit.should == ['Time', 'Gift', 'Senders', 'Other Receivers']
    (table/"tbody tr").map{|x| (x/:td).mapit[1..-1]}.should == [['G3', 'P1, P3', ''], %w'G4 P3 P2']

    c = content('/reports/by_sender', :title=>'Gifts by Sender', :session=>session)
    tables = c/:table
    tables.mapcaption.should == %w'P1 P3'
    table = tables.first
    (table/:th).mapit.should == ['Time', 'Gift', 'Receivers', 'Other Senders']
    (table/"tbody tr").map{|x| (x/:td).mapit[1..-1]}.should == [['G1', 'P2', ''], ['G2', 'P2', ''], %w'G3 P4 P3']
    table = tables.last
    (table/:th).mapit.should == ['Time', 'Gift', 'Receivers', 'Other Senders']
    (table/"tbody tr").map{|x| (x/:td).mapit[1..-1]}.should == [%w'G3 P4 P1', ['G4', 'P2, P4', '']]

    c = content('/reports/summary', :title=>'Gift Summary', :session=>session)
    (c/:h3).mapit.should == ['Total Number of Gifts: 4']
    tables = c/:table
    tables.mapcaption.should == ['Totals By Sender', 'Totals By Receiver']
    table = tables.first
    (table/:th).mapit.should == ['Sender', 'Number of Gifts']
    (table/"tbody tr").map{|x| (x/:td).mapit}.should == [%w'P1 3', %w'P3 2']
    table = tables.last
    (table/:th).mapit.should == ['Receiver', 'Number of Gifts']
    (table/"tbody tr").map{|x| (x/:td).mapit}.should == [%w'P2 3', %w'P4 2']

    c = content('/reports/crosstab', :title=>'Gift Summary Crosstab', :session=>session)
    tables = c/:table
    tables.length.should == 1
    table = tables.first
    (table/:th).mapit.should == ['Sender\Receiver', 'P2', 'P4']
    (table/"tbody tr").map{|x| (x/:td).mapit}.should == [%w'P1 2 1', %w'P3 1 2']
  end

  specify "users can't see other other users events, people, or gifts" do
    session = sign_in('jeremy')
    j = create_user('j')
    je = Event.create(:user_id=>j.id, :name=>'JE')
    jp = Person.create(:user_id=>j.id, :name=>'JP')
    jg = Gift.create(:event_id=>je.id, :name=>'JG')
    jeremye = Event.exclude(:user_id=>j.id).first

    (content('/choose_event', :session=>session)/:option).mapit.should == %w'Christmas'
    (content("/manage/edit_event_receivers/#{jeremye.id}", :session=>session)/:option).mapit.should == []
    (content("/manage/edit_event_senders/#{jeremye.id}", :session=>session)/:option).mapit.should == []
    (content("/manage/show_event", :session=>session)/:option).mapit.should == ['', 'Christmas']
    (content("/manage/show_gift", :session=>session)/:option).mapit.should == ['']
    (content("/manage/show_person", :session=>session)/:option).mapit.should == ['']
    (content("/", :session=>session)/:option).mapit.should == []
    content("/reports/chronological", :session=>session).it.should_not =~ /J[EPG]/
    content("/reports/by_sender", :session=>session).it.should_not =~ /J[EPG]/
    content("/reports/by_receiver", :session=>session).it.should_not =~ /J[EPG]/
    content("/reports/summary", :session=>session).it.should_not =~ /J[EPG]/
    content("/reports/crosstab", :session=>session).it.should_not =~ /J[EPG]/
  end
end