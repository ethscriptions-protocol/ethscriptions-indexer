# Welcome to the official Open Source Ethscriptions Indexer!

This indexer has been extracted and streamlined from the indexer that runs Ethscriptions.com. This indexer has been validated as producing the same results against the live Ethscriptions.com indexer.

## Important: When pulling changes!

Always run `bundle install && rails db:migrate` after you pull in the latest changes.

## Installation Instructions

This is a Ruby on Rails app.

Run this command inside the directory of your choice to clone the repository:

```!bash
git clone https://github.com/ethscriptions-protocol/ethscriptions-indexer
```

If you don't already have Ruby Version Manager installed, install it:

```bash
curl -sSL https://get.rvm.io | bash -s stable
```

You might need to run this if there is an issue with gpg:

```bash
gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
```

Now install ruby 3.2.2:

```bash
rvm install 3.2.2
```

On a Mac you might run into an issue with openssl. If you do you might need to run something like this:

```bash
rvm install 3.2.2 --with-openssl-dir=$(brew --prefix openssl@1.1)
```

Install the gems (libraries) the app needs:

```bash
bundle install
```

Install postgres if you don't already have it:

Mac: `brew install postgresql`

Ubuntu: `sudo apt-get install libpq-dev`

RHEL: `yum install postgresql-devel`

Alpine: `apk add postgresql-dev`

Set up your env vars by renaming `.sample.env` to `.env`, `.sample.env.development` to `.env.development`, and `.sample.env.test` to `.env.test`. These environment-specific env files just set the database you're using in each environment. You have the option of using a replica database for reads, but you can just leave this blank if you don't want to use it. There's also a `.sample.env.production` but you'll probably want to set production env vars at the system level.

Create the database:

```bash
rails db:create
```

Migrate the database schema:

```bash
rails db:migrate
```

You will also need memcache to use this. You can install it with homebrew as well. Consult ChatGPT!

You will need an Alchemy API key for this to work!

Run the tests to make sure everything is set up correctly:

```bash
rspec
```

Now run the process to index ethscriptions!

```bash
bundle exec clockwork config/main_importer_clock.rb
```

You'll want to keep this running in the background so you can process everything. If your indexer instance is behind and you want to catch up quickly you can adjust the `BLOCK_IMPORT_BATCH_SIZE` in your `.env`. With Alchemy you can set this as high as 30 and still see a performance improvement.

Now start the web server on a port of your choice, for example 4000:

```bash
rails s -p 4000
```

You can use this web server to access the API!

Try `http://localhost:4000/ethscriptions/0/data` to see the cat made famous in the first ethscription or `http://localhost:4000/blocks/:number` to see details of any block.
